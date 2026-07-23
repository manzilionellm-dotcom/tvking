'use strict';

/**
 * config.js — Lecture et validation de la configuration du gateway 7 MOTION.
 *
 * Toute la configuration passe par des variables d'environnement (fichier .env
 * chargé par docker-compose, ou export shell). AUCUN secret n'est écrit en dur
 * ici : seuls des DÉFAUTS SÛRS sont fournis. Voir gateway/.env.example.
 *
 * Rappel du modèle de capacité (contrainte fournisseur dure) :
 *   - La ligne amont a un `max_connections` FAIBLE (souvent 1).
 *   - Le gateway ne tire donc en amont QUE `PROVIDER_MAX_CONNECTIONS` chaînes
 *     DISTINCTES à la fois (1 connexion fournisseur par chaîne mutualisée).
 *   - Mais il sert un nombre ILLIMITÉ de spectateurs sur CHACUNE de ces chaînes,
 *     borné seulement par `BROADCAST_MAX_STREAMS` (nombre de sockets clients).
 *   → 500 spectateurs sur LA MÊME chaîne = 1 connexion amont. ✅
 *   → 500 spectateurs sur des chaînes DIFFÉRENTES = borné par le fournisseur. ❌
 */

/** Convertit une variable d'env en entier, avec repli sur `def` si absente/invalide. */
function intEnv(name, def) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') return def;
  const n = Number.parseInt(String(raw), 10);
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`Variable ${name} invalide : "${raw}" (entier positif attendu)`);
  }
  return n;
}

/** Lit une chaîne d'env, repli sur `def`. */
function strEnv(name, def) {
  const raw = process.env[name];
  return raw === undefined || raw === null || raw === '' ? def : String(raw);
}

/** Normalise une base d'URL : retire le/les slash(s) de fin. */
function normalizeBase(url) {
  if (!url) return url;
  return String(url).replace(/\/+$/, '');
}

/**
 * Construit l'objet de configuration à partir de l'environnement (ou d'un objet
 * fourni pour les tests). Lève une erreur claire si une valeur obligatoire manque
 * en production.
 *
 * @param {NodeJS.ProcessEnv} [env=process.env]
 * @param {{ requireUpstream?: boolean }} [opts]
 */
function loadConfig(env = process.env, opts = {}) {
  // On bascule temporairement process.env pour réutiliser intEnv/strEnv.
  const previous = process.env;
  process.env = env;
  try {
    const cfg = {
      // ---- Réseau / façade ----------------------------------------------------
      // Port d'écoute HTTP interne (Caddy termine le TLS et proxifie ici).
      PORT: intEnv('PORT', 8088),
      // Interface d'écoute (0.0.0.0 = toutes ; dans Docker c'est le réseau interne).
      HOST: strEnv('HOST', '0.0.0.0'),
      // URL publique HTTPS du gateway (domaine réel), utilisée pour réécrire les
      // URLs dans les playlists → la ligne fournisseur réelle n'apparaît JAMAIS.
      PUBLIC_BASE: normalizeBase(strEnv('PUBLIC_BASE', '')),

      // ---- Amont (fournisseur) ------------------------------------------------
      // Serveur fournisseur (ex. http://ligne.fournisseur.tld:8080).
      UPSTREAM_BASE: normalizeBase(strEnv('UPSTREAM_BASE', '')),
      UPSTREAM_USER: strEnv('UPSTREAM_USER', ''),
      UPSTREAM_PASS: strEnv('UPSTREAM_PASS', ''),
      // CONTRAINTE DURE : nombre max de connexions amont simultanées = nombre max
      // de chaînes DISTINCTES tirables en même temps. C'est la vraie limite de la
      // ligne (souvent 1). On ne la dépasse JAMAIS.
      PROVIDER_MAX_CONNECTIONS: intEnv('PROVIDER_MAX_CONNECTIONS', 1),

      // ---- Diffusion (identité que les apps utilisent) ------------------------
      BROADCAST_USER: strEnv('BROADCAST_USER', ''),
      BROADCAST_PASS: strEnv('BROADCAST_PASS', ''),
      // Nombre max de spectateurs (sockets clients) simultanés, TOUTES chaînes
      // confondues. Défaut porté à 500+ pour tenir l'objectif de charge.
      BROADCAST_MAX_STREAMS: intEnv('BROADCAST_MAX_STREAMS', 500),

      // ---- Mémoire / backpressure --------------------------------------------
      // Tampon max par client avant de le considérer « lent » et de le couper.
      // 8 Mo/client : assez pour absorber un hoquet réseau sans exploser la RAM.
      CLIENT_BUFFER_MAX_BYTES: intEnv('CLIENT_BUFFER_MAX_BYTES', 8 * 1024 * 1024),
      // Plafond GLOBAL de mémoire tampon cumulée sur TOUS les clients.
      // À 500 clients, 128 Mo = 256 Ko/client (trop juste). On monte à 512 Mo par
      // défaut (≈ 1 Mo/client à 500), ajustable selon la RAM du VPS (voir README).
      GLOBAL_CLIENT_BUFFER_MAX_BYTES: intEnv(
        'GLOBAL_CLIENT_BUFFER_MAX_BYTES',
        512 * 1024 * 1024,
      ),
      // Fréquence du balayage de backpressure (coupe des clients lents).
      SWEEP_INTERVAL_MS: intEnv('SWEEP_INTERVAL_MS', 1000),

      // ---- Réseau / robustesse ------------------------------------------------
      // Délai d'inactivité amont avant de considérer la source morte (ms).
      UPSTREAM_TIMEOUT_MS: intEnv('UPSTREAM_TIMEOUT_MS', 30000),
      // keep-alive TCP côté sockets (amont et clients).
      KEEPALIVE_MS: intEnv('KEEPALIVE_MS', 15000),
      // Nombre de tentatives de reconnexion amont avant d'abandonner une chaîne.
      UPSTREAM_MAX_RETRIES: intEnv('UPSTREAM_MAX_RETRIES', 3),
      // Délai de base entre reconnexions amont (backoff exponentiel).
      UPSTREAM_RETRY_BASE_MS: intEnv('UPSTREAM_RETRY_BASE_MS', 500),

      // ---- Journalisation -----------------------------------------------------
      LOG_LEVEL: strEnv('LOG_LEVEL', 'info'), // error|warn|info|debug
    };

    // Validation « production » (désactivable pour les tests unitaires/charge).
    if (opts.requireUpstream) {
      const missing = [];
      if (!cfg.UPSTREAM_BASE) missing.push('UPSTREAM_BASE');
      if (!cfg.BROADCAST_USER) missing.push('BROADCAST_USER');
      if (!cfg.BROADCAST_PASS) missing.push('BROADCAST_PASS');
      if (missing.length) {
        throw new Error(
          `Configuration incomplète — variables manquantes : ${missing.join(', ')}. ` +
            `Voir gateway/.env.example`,
        );
      }
    }

    if (cfg.PROVIDER_MAX_CONNECTIONS < 1) {
      throw new Error('PROVIDER_MAX_CONNECTIONS doit être ≥ 1');
    }
    // Garde-fou : le plafond global doit pouvoir contenir au moins quelques
    // clients à pleine charge, sinon la config est incohérente.
    if (cfg.GLOBAL_CLIENT_BUFFER_MAX_BYTES < cfg.CLIENT_BUFFER_MAX_BYTES) {
      throw new Error(
        'GLOBAL_CLIENT_BUFFER_MAX_BYTES doit être ≥ CLIENT_BUFFER_MAX_BYTES',
      );
    }

    return cfg;
  } finally {
    process.env = previous;
  }
}

module.exports = { loadConfig, intEnv, strEnv, normalizeBase };
