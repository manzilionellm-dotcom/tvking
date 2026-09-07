// =========================================================
//  app_versions.js — « CETTE BOX EST-ELLE À JOUR ? », côté serveur
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (07/09/2026), mot pour mot : « si je mets
//  l'adresse Mac, je vois exactement le numéro de l'application, si c'est
//  le dernier… ancienne version, dernière version ».
//
//  Aujourd'hui le panel affiche bien une version (colonne devices.
//  app_version, remplie par le heartbeat) — mais il faut CONNAÎTRE par
//  cœur le dernier numéro publié pour savoir si le client est en retard.
//  Au téléphone, avec un client qui attend, c'est inutilisable.
//
//  Ce module répond à la question à la place de l'humain : il va lire le
//  `version.json` RÉELLEMENT publié sur le canal de la plateforme, et le
//  compare au numéro que la box a remonté.
//
//  ---------------------------------------------------------
//  POURQUOI UN MODULE SÉPARÉ (même raison que device_profiles.js)
//  ---------------------------------------------------------
//  Deux appelants au moins :
//    • api_v1.js → GET /api/v1/devices/:id/overview (la fiche MAC du
//      panel, celle que le patron ouvre au téléphone) ;
//    • api_v1.js → GET /api/v1/app-versions (le bandeau « dernier numéro
//      publié » du panel, sans avoir à choisir un appareil).
//  Et demain le worker public, si l'app veut le même verdict.
//
//  Recopier le calcul aurait créé deux vérités : le jour où l'une dérive,
//  le panel dirait « à jour » pendant que la box propose une mise à jour.
//  Le support ne saurait plus quoi croire. Une seule implémentation.
//
//  Les helpers HTTP ne sont pas importés : ce module ne fait QUE de la
//  logique et une lecture réseau. C'est l'appelant qui emballe en JSON,
//  avec SES en-têtes (worker.js et api_v1.js n'ont pas les mêmes).
// =========================================================

// ---------------------------------------------------------
//  LE CANAL DE CHAQUE APP — exactement celui que l'app lit
// ---------------------------------------------------------
//  Ces deux tags ne sont pas choisis ici : ils sont RECOPIÉS de
//  lib/core/update/update_service.dart, qui est ce que le bouton
//  « Vérifier les mises à jour » interroge sur la box :
//
//    TV     → TV_UPDATE_TAG, défaut 'seventv-latest'
//    Mobile → 'prod' (la maison mère ; les autres canaux sont des essais)
//
//  Le verdict du panel doit dire LA MÊME CHOSE que le bouton de l'app.
//  Si on visait un autre canal, le panel afficherait « ancienne version »
//  sur une box que l'app déclare à jour — et personne ne s'y retrouverait.
export const VERSION_CHANNELS = {
  tv: 'seventv-latest',
  mobile: 'prod',
};

/// Base des releases GitHub (même dépôt que le miroir /r/<tag>/<asset>).
export const RELEASE_BASE =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download';

/// URL du manifeste publié pour une plateforme, ou null si inconnue.
export function manifestUrl(platform) {
  const tag = VERSION_CHANNELS[String(platform || '').toLowerCase()];
  return tag ? `${RELEASE_BASE}/${tag}/version.json` : null;
}

// ---------------------------------------------------------
//  COMPARER DEUX NUMÉROS LISIBLES (19881, 19882, … 198810)
// ---------------------------------------------------------
//  Rappel AGENTS.md (« la règle de la maison ») : le buildLabel vaut
//  1988 (l'année du propriétaire) suivi d'un compteur qui ne fait que
//  monter. Le préfixe étant FIXE et le compteur MONOTONE, la comparaison
//  numérique suffit et reste juste au passage à deux chiffres :
//  198810 > 19889, parce que 198810 est vraiment le plus grand nombre.
//
//  On ne compare JAMAIS en texte ('19889' > '198810' en ordre
//  alphabétique — l'inverse de la vérité).
//
//  Retour : -1 (a plus ancien), 0 (identiques), 1 (a plus récent),
//  ou null si l'un des deux n'est pas un nombre exploitable.
export function compareLabels(a, b) {
  const na = Number.parseInt(String(a == null ? '' : a).trim(), 10);
  const nb = Number.parseInt(String(b == null ? '' : b).trim(), 10);
  if (!Number.isFinite(na) || !Number.isFinite(nb)) return null;
  if (na === nb) return 0;
  return na < nb ? -1 : 1;
}

// ---------------------------------------------------------
//  LE VERDICT
// ---------------------------------------------------------
//  Quatre états, et un seul se lit « tout va bien » :
//
//    'latest'   → la box porte exactement le numéro publié ;
//    'outdated' → elle est en RETARD : c'est LE cas qui explique
//                 « le client dit que ça ne marche pas » ;
//    'ahead'    → elle porte un numéro PLUS GRAND que le publié. Ce
//                 n'est pas une erreur : ce sont les box de labo du
//                 patron, qui tournent sur un build pas encore publié ;
//    'unknown'  → on ne sait pas, et on le DIT plutôt que de deviner :
//                 vieille app d'avant le numéro lisible, plateforme
//                 inconnue, ou GitHub injoignable à cet instant.
//
//  RÈGLE DE SECOURS. Les apps installées AVANT le 07/09/2026 ne
//  connaissent pas `buildLabel` — elles ne remontent que `appBuild`
//  (le versionCode, un horodatage). On compare alors les versionCode :
//  c'est exactement ce que fait le bouton de mise à jour dans l'app, donc
//  le verdict reste cohérent. On le signale par `basis: 'versionCode'`
//  pour que le panel n'affiche pas un numéro court qui n'existe pas.
export function versionVerdict(installed, published) {
  const inst = installed || {};
  const pub = published || {};
  const instLabel = String(inst.buildLabel == null ? '' : inst.buildLabel).trim();
  const pubLabel = String(pub.buildLabel == null ? '' : pub.buildLabel).trim();

  // 1) Chemin normal : les deux côtés ont le numéro lisible.
  const byLabel = instLabel && pubLabel ? compareLabels(instLabel, pubLabel) : null;
  if (byLabel !== null) {
    return {
      state: byLabel === 0 ? 'latest' : byLabel < 0 ? 'outdated' : 'ahead',
      basis: 'buildLabel',
      installed: instLabel,
      latest: pubLabel,
    };
  }

  // 2) Secours : le versionCode Android (horodatage strictement croissant).
  const instCode = Number.parseInt(String(inst.appBuild == null ? '' : inst.appBuild), 10);
  const pubCode = Number.parseInt(String(pub.versionCode == null ? '' : pub.versionCode), 10);
  if (Number.isFinite(instCode) && instCode > 0
      && Number.isFinite(pubCode) && pubCode > 0) {
    return {
      state: instCode === pubCode ? 'latest' : instCode < pubCode ? 'outdated' : 'ahead',
      basis: 'versionCode',
      installed: String(instCode),
      latest: pubLabel || String(pubCode),
    };
  }

  // 3) On ne sait pas. On ne bluffe pas.
  return {
    state: 'unknown',
    basis: 'none',
    installed: instLabel || (Number.isFinite(instCode) && instCode > 0 ? String(instCode) : ''),
    latest: pubLabel || (Number.isFinite(pubCode) && pubCode > 0 ? String(pubCode) : ''),
  };
}

// ---------------------------------------------------------
//  LIRE LE MANIFESTE PUBLIÉ — avec un cache, obligatoirement
// ---------------------------------------------------------
//  Sans cache, chaque ouverture de fiche MAC dans le panel déclencherait
//  un appel à GitHub. Le panel se rafraîchit en boucle sur la page
//  « En ligne » : on se ferait limiter (403) en quelques minutes, et le
//  verdict deviendrait « unknown » précisément quand on en a besoin.
//
//  Cache MÉMOIRE PAR ISOLATE, même motif que `_insightsOverviewCache`
//  (api_v1.js) et `_trendingCache` (worker.js). 10 minutes : une
//  publication n'arrive pas dix fois par heure, et l'écart maximal entre
//  « publié » et « affiché » reste inférieur au temps d'un appel client.
export const PUBLISHED_TTL_MS = 10 * 60 * 1000;
//  Échec (GitHub down, réseau coupé) : on retient l'échec 60 s. Assez
//  pour ne pas marteler l'amont pendant une panne, assez court pour que
//  le verdict revienne vite quand ça remarche.
export const PUBLISHED_FAIL_TTL_MS = 60 * 1000;

const _cache = new Map(); // platform → { at, ok, data }

/// Vide le cache — réservé aux tests (smoke), jamais appelé en prod.
export function resetPublishedCache() {
  _cache.clear();
}

/// Le manifeste publié pour une plateforme ('tv' | 'mobile').
///
/// Renvoie `{ platform, channel, buildLabel, versionCode, version, at }`
/// ou `null` si on n'a pas pu lire (plateforme inconnue, réseau, JSON
/// cassé). JAMAIS d'exception : une fiche MAC ne doit pas tomber parce
/// que GitHub tousse — le panel affiche alors « inconnu », c'est tout.
export async function publishedVersion(platform, opts) {
  const o = opts || {};
  const fetchImpl = o.fetchImpl || globalThis.fetch;
  const now = typeof o.now === 'number' ? o.now : Date.now();
  const key = String(platform || '').toLowerCase();
  const url = manifestUrl(key);
  if (!url) return null;

  const hit = _cache.get(key);
  if (hit) {
    const ttl = hit.ok ? PUBLISHED_TTL_MS : PUBLISHED_FAIL_TTL_MS;
    if (now - hit.at < ttl) return hit.data;
  }

  let data = null;
  try {
    // `redirect: 'follow'` : GitHub renvoie un 302 vers son CDN d'objets.
    // 8 s de garde — le panel attend, on ne le laisse pas pendre.
    const resp = await fetchImpl(url, {
      redirect: 'follow',
      headers: {
        'Accept': 'application/json',
        // Un Worker n'envoie pas d'User-Agent par défaut, et GitHub
        // répond parfois une page de blocage dans ce cas (même piège que
        // _sportsHeaders() dans worker.js).
        'User-Agent': 'Mozilla/5.0 (compatible; 7MOTION/1.0; +https://app.7themotion.com)',
      },
      signal: typeof AbortSignal !== 'undefined' && AbortSignal.timeout
        ? AbortSignal.timeout(8000)
        : undefined,
    });
    if (resp && resp.ok) {
      const j = await resp.json();
      if (j && typeof j === 'object') {
        data = {
          platform: key,
          channel: VERSION_CHANNELS[key],
          buildLabel: String(j.buildLabel == null ? '' : j.buildLabel).trim(),
          versionCode: Number.parseInt(String(j.versionCode == null ? '' : j.versionCode), 10) || 0,
          version: String(j.version == null ? '' : j.version).trim(),
          at: now,
        };
      }
    }
  } catch (_) {
    // Réseau, timeout, JSON invalide : on retombe sur `data = null`.
    data = null;
  }

  _cache.set(key, { at: now, ok: data !== null, data });
  return data;
}

/// Les manifestes des DEUX plateformes d'un coup (bandeau du panel).
/// Les deux lectures sont indépendantes → en parallèle.
export async function publishedVersions(opts) {
  const [tv, mobile] = await Promise.all([
    publishedVersion('tv', opts),
    publishedVersion('mobile', opts),
  ]);
  return { tv, mobile };
}

/// Raccourci pour la fiche MAC : lit le manifeste de la plateforme de
/// l'appareil et rend le verdict. `device` = la ligne `devices`
/// (build_label, app_build, platform).
export async function deviceVersionStatus(device, opts) {
  const d = device || {};
  const platform = String(d.platform || '').toLowerCase();
  const published = await publishedVersion(platform, opts);
  const v = versionVerdict(
    { buildLabel: d.build_label, appBuild: d.app_build },
    published,
  );
  return {
    ...v,
    platform: platform || null,
    channel: published ? published.channel : (VERSION_CHANNELS[platform] || null),
    // Version « marketing » publiée (0.3.3) — utile en support quand le
    // client lit l'écran « À propos » à voix haute.
    latestVersion: published ? published.version : '',
    latestVersionCode: published ? published.versionCode : 0,
  };
}
