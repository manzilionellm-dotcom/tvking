'use strict';

/**
 * hub.js — Mutualisation amont + fan-out multi-spectateurs.
 *
 * PRINCIPE CENTRAL (le « secret » qui permet 500 spectateurs sur 1 connexion) :
 *   - Pour une chaîne donnée, on ouvre UNE SEULE connexion amont (`_pump`).
 *   - Chaque octet reçu de l'amont est ré-émis TEL QUEL à TOUS les abonnés
 *     (fan-out O(N) : une boucle, N `res.write(chunk)`, ZÉRO copie du buffer).
 *   - Node partage la même référence Buffer entre tous les sockets → pas de
 *     duplication mémoire du payload ; seule la file d'attente par socket coûte.
 *
 * CONTRAINTE FOURNISSEUR (dure) :
 *   - Le nombre de chaînes ouvertes SIMULTANÉMENT (donc de `_pump` actifs) ne
 *     dépasse JAMAIS `PROVIDER_MAX_CONNECTIONS`. Une demande d'une (N+1)ᵉ chaîne
 *     distincte est refusée proprement (le serveur répond 503).
 *   - Le nombre d'abonnés sur UNE chaîne est illimité (borné seulement par
 *     `BROADCAST_MAX_STREAMS`, géré côté serveur).
 *
 * BACKPRESSURE (ne jamais laisser un lent bloquer les autres) :
 *   - On n'attend JAMAIS le `drain` d'un client dans le `_pump`. Un client lent
 *     accumule dans SA propre file de socket ; le `_pump` continue à pousser le
 *     live aux autres sans ralentir.
 *   - Un balayage périodique (`_sweepBackpressure`) coupe les clients dont la
 *     file dépasse `CLIENT_BUFFER_MAX_BYTES`, ou, si le cumul global dépasse
 *     `GLOBAL_CLIENT_BUFFER_MAX_BYTES`, coupe d'abord les plus lents.
 */

const http = require('node:http');
const https = require('node:https');
const { EventEmitter } = require('node:events');

/** Petit logger à niveaux, sans dépendance. */
function makeLogger(level) {
  const order = { error: 0, warn: 1, info: 2, debug: 3 };
  const threshold = order[level] ?? 2;
  const emit = (lvl, ...args) => {
    if ((order[lvl] ?? 2) <= threshold) {
      // eslint-disable-next-line no-console
      console[lvl === 'debug' ? 'log' : lvl](`[hub:${lvl}]`, ...args);
    }
  };
  return {
    error: (...a) => emit('error', ...a),
    warn: (...a) => emit('warn', ...a),
    info: (...a) => emit('info', ...a),
    debug: (...a) => emit('debug', ...a),
  };
}

/**
 * Un abonné = un socket client (la réponse HTTP en cours vers un spectateur).
 * On garde une trace de son état pour la journalisation et le backpressure.
 */
class Subscriber {
  constructor(id, res, meta = {}) {
    this.id = id;
    this.res = res; // http.ServerResponse (vers le spectateur)
    this.meta = meta; // { ip, ua, ... } pour les logs
    this.bytesSent = 0;
    this.alive = true;
    this.createdAt = Date.now();
  }

  /** Octets actuellement en attente d'envoi dans la file du socket (backpressure). */
  get buffered() {
    // writableLength = octets tamponnés par Node non encore remis à l'OS.
    return this.res && this.res.writableLength ? this.res.writableLength : 0;
  }
}

/**
 * Une chaîne mutualisée : 1 connexion amont, N abonnés.
 */
class Channel {
  constructor(key, upstreamUrl, hub) {
    this.key = key; // identifiant logique (ex. id de flux)
    this.upstreamUrl = upstreamUrl; // URL amont réelle (jamais exposée)
    this.hub = hub;
    this.subscribers = new Map(); // subId -> Subscriber
    this.upstreamReq = null; // requête amont en cours
    this.upstreamRes = null; // réponse amont (le flux)
    this.headers = null; // en-têtes amont à recopier aux clients (content-type…)
    this.opening = false; // true tant que la connexion amont n'est pas établie
    this.closed = false;
    this.retries = 0;
    this.bytesIn = 0; // total octets reçus de l'amont
    this.startedAt = Date.now();
    this._retryTimer = null;
  }

  get size() {
    return this.subscribers.size;
  }
}

class Hub extends EventEmitter {
  /**
   * @param {object} config — objet issu de loadConfig()
   * @param {object} [deps] — injections pour les tests (ex. httpModule)
   */
  constructor(config, deps = {}) {
    super();
    this.config = config;
    this.log = deps.logger || makeLogger(config.LOG_LEVEL);
    // Injection possible d'un module http factice pour les tests.
    this._httpGet = deps.httpGet || null;

    this.channels = new Map(); // key -> Channel
    this._subSeq = 0; // séquence d'identifiants d'abonnés

    // Balayage périodique de backpressure : coupe les clients lents.
    // unref() : ne maintient pas le process en vie à lui seul.
    this._sweepTimer = setInterval(
      () => this._sweepBackpressure(),
      Math.max(200, config.SWEEP_INTERVAL_MS),
    );
    if (this._sweepTimer.unref) this._sweepTimer.unref();
  }

  /** Nombre de connexions amont actives (= chaînes ouvertes). */
  get activeUpstreams() {
    let n = 0;
    for (const ch of this.channels.values()) {
      if (!ch.closed) n += 1;
    }
    return n;
  }

  /** Nombre total d'abonnés, toutes chaînes confondues. */
  get totalSubscribers() {
    let n = 0;
    for (const ch of this.channels.values()) n += ch.size;
    return n;
  }

  /** Cumul des octets tamponnés côté clients (pour le plafond global). */
  get totalBuffered() {
    let n = 0;
    for (const ch of this.channels.values()) {
      for (const sub of ch.subscribers.values()) n += sub.buffered;
    }
    return n;
  }

  /**
   * Abonne un spectateur à une chaîne. Ouvre la connexion amont si c'est la
   * première demande pour cette chaîne — en respectant PROVIDER_MAX_CONNECTIONS.
   *
   * @param {string} channelKey — identifiant logique de la chaîne
   * @param {string} upstreamUrl — URL amont réelle à ouvrir si nécessaire
   * @param {http.ServerResponse} res — la réponse HTTP vers le spectateur
   * @param {object} [meta] — infos de log (ip, ua…)
   * @returns {{ ok: true, subscriber: Subscriber } |
   *            { ok: false, code: number, reason: string }}
   */
  subscribe(channelKey, upstreamUrl, res, meta = {}) {
    if (this.closed) {
      return { ok: false, code: 503, reason: 'gateway en arrêt' };
    }

    let channel = this.channels.get(channelKey);

    // Cas d'une NOUVELLE chaîne : vérifier la limite fournisseur AVANT d'ouvrir.
    if (!channel) {
      if (this.activeUpstreams >= this.config.PROVIDER_MAX_CONNECTIONS) {
        // On refuse proprement : la ligne fournisseur ne peut pas tirer une
        // chaîne distincte de plus. Pas de crash, pas de connexion amont ouverte.
        this.log.warn(
          `Refus chaîne "${channelKey}" : ${this.activeUpstreams}/${this.config.PROVIDER_MAX_CONNECTIONS} connexions amont déjà utilisées`,
        );
        return {
          ok: false,
          code: 503,
          reason:
            'Limite fournisseur atteinte (PROVIDER_MAX_CONNECTIONS) : ' +
            'trop de chaînes distinctes simultanées. ' +
            'Cette ligne ne mutualise que ' +
            this.config.PROVIDER_MAX_CONNECTIONS +
            ' flux distinct(s) à la fois.',
        };
      }
      channel = new Channel(channelKey, upstreamUrl, this);
      this.channels.set(channelKey, channel);
      this.log.info(
        `Ouverture chaîne "${channelKey}" (amont ${this.activeUpstreams + 1}/${this.config.PROVIDER_MAX_CONNECTIONS})`,
      );
      this._openUpstream(channel);
    }

    // Crée l'abonné et l'enregistre.
    const sub = new Subscriber(`c${++this._subSeq}`, res, meta);
    channel.subscribers.set(sub.id, sub);

    // Si l'amont a déjà envoyé ses en-têtes, on les recopie tout de suite au
    // nouveau client (content-type, etc.). Sinon ce sera fait à l'ouverture.
    if (channel.headers && !res.headersSent) {
      this._applyUpstreamHeaders(res, channel.headers);
    }

    // Nettoyage automatique quand le client se déconnecte.
    const onClose = () => this._removeSubscriber(channel, sub.id, 'client fermé');
    res.on('close', onClose);
    res.on('error', () => this._removeSubscriber(channel, sub.id, 'erreur client'));

    this.log.debug(
      `+ abonné ${sub.id} sur "${channelKey}" (${channel.size} abonnés sur cette chaîne)`,
    );
    this.emit('subscribe', { channelKey, subId: sub.id, size: channel.size });

    return { ok: true, subscriber: sub };
  }

  /** Retire un abonné, et ferme la chaîne (donc l'amont) si plus personne. */
  _removeSubscriber(channel, subId, why) {
    const sub = channel.subscribers.get(subId);
    if (!sub) return;
    sub.alive = false;
    channel.subscribers.delete(subId);
    this.log.debug(
      `- abonné ${subId} de "${channel.key}" (${why}) — reste ${channel.size}`,
    );
    this.emit('unsubscribe', { channelKey: channel.key, subId, size: channel.size });

    // Plus aucun spectateur → on relâche la connexion fournisseur.
    // C'est CE qui libère un « slot » amont pour une autre chaîne.
    if (channel.size === 0) {
      this._closeChannel(channel, 'plus aucun abonné');
    }
  }

  /**
   * Ouvre l'UNIQUE connexion amont pour une chaîne et branche le `_pump`.
   * En cas de coupure amont, tente une reconnexion avec backoff exponentiel.
   */
  _openUpstream(channel) {
    if (channel.closed) return;
    channel.opening = true;

    const url = channel.upstreamUrl;
    const isHttps = url.startsWith('https:');
    const mod = isHttps ? https : http;

    // Permet d'injecter un amont factice dans les tests (getUpstream).
    const doGet = this._httpGet || mod.get.bind(mod);

    const options = {
      // keep-alive TCP côté amont : évite de reconstruire la socket à chaque octet.
      headers: {
        'User-Agent': 'gateway-7motion/1.0',
        Connection: 'keep-alive',
      },
      // Timeout d'établissement/inactivité.
      timeout: this.config.UPSTREAM_TIMEOUT_MS,
    };

    this.log.debug(`_pump: connexion amont pour "${channel.key}" → ${url}`);

    const req = doGet(url, options, (res) => {
      channel.opening = false;
      channel.retries = 0; // succès → on remet le compteur de retry à zéro
      channel.upstreamRes = res;
      channel.headers = res.headers || {};

      // Statut amont non-2xx → on abandonne cette chaîne proprement.
      if (res.statusCode && (res.statusCode < 200 || res.statusCode >= 300)) {
        this.log.warn(
          `Amont "${channel.key}" a répondu ${res.statusCode} → abandon`,
        );
        res.resume(); // vide le flux pour libérer la socket
        this._failChannel(channel, `amont statut ${res.statusCode}`);
        return;
      }

      // Recopie les en-têtes amont utiles à tous les abonnés déjà connectés.
      for (const sub of channel.subscribers.values()) {
        if (!sub.res.headersSent) {
          this._applyUpstreamHeaders(sub.res, channel.headers);
        }
      }

      // ---- LE FAN-OUT : un seul flux lu, ré-émis à tous ----------------------
      res.on('data', (chunk) => {
        channel.bytesIn += chunk.length;
        // O(N) : on parcourt les abonnés et on écrit LA MÊME référence chunk.
        // Aucune copie du payload. `write()` renvoie false si la file du client
        // est pleine — on NE bloque PAS pour autant : le balayage coupera ce
        // client s'il reste durablement en retard.
        for (const sub of channel.subscribers.values()) {
          if (!sub.alive) continue;
          try {
            sub.res.write(chunk);
            sub.bytesSent += chunk.length;
          } catch {
            // Socket client déjà mort : on le retirera au prochain tick.
            sub.alive = false;
          }
        }
      });

      res.on('end', () => {
        this.log.info(`Amont "${channel.key}" terminé (fin de flux)`);
        this._failChannel(channel, 'fin de flux amont');
      });

      res.on('error', (err) => {
        this.log.warn(`Erreur flux amont "${channel.key}": ${err.message}`);
        this._failChannel(channel, `erreur amont: ${err.message}`);
      });
    });

    req.on('error', (err) => {
      channel.opening = false;
      this.log.warn(`Connexion amont "${channel.key}" échouée: ${err.message}`);
      this._failChannel(channel, `connexion amont: ${err.message}`);
    });

    if (req.setTimeout) {
      req.setTimeout(this.config.UPSTREAM_TIMEOUT_MS, () => {
        this.log.warn(`Timeout amont "${channel.key}"`);
        req.destroy(new Error('timeout'));
      });
    }

    channel.upstreamReq = req;
  }

  /**
   * Gère un échec amont : tente une reconnexion (backoff) tant qu'il reste des
   * abonnés et qu'on n'a pas épuisé les essais ; sinon ferme proprement (les
   * clients reçoivent une fin de flux, pas un crash).
   */
  _failChannel(channel, why) {
    if (channel.closed) return;
    channel.upstreamRes = null;
    channel.upstreamReq = null;

    // Plus personne n'écoute : inutile de reconnecter.
    if (channel.size === 0) {
      this._closeChannel(channel, `${why} (aucun abonné)`);
      return;
    }

    if (channel.retries >= this.config.UPSTREAM_MAX_RETRIES) {
      this.log.error(
        `Chaîne "${channel.key}" abandonnée après ${channel.retries} essais (${why})`,
      );
      this._closeChannel(channel, `échecs amont répétés (${why})`);
      return;
    }

    channel.retries += 1;
    const delay =
      this.config.UPSTREAM_RETRY_BASE_MS * 2 ** (channel.retries - 1);
    this.log.warn(
      `Reconnexion amont "${channel.key}" dans ${delay}ms (essai ${channel.retries}/${this.config.UPSTREAM_MAX_RETRIES}) — ${why}`,
    );
    channel._retryTimer = setTimeout(() => {
      if (!channel.closed && channel.size > 0) this._openUpstream(channel);
    }, delay);
    if (channel._retryTimer.unref) channel._retryTimer.unref();
  }

  /** Ferme une chaîne : coupe l'amont, termine les réponses clients restantes. */
  _closeChannel(channel, why) {
    if (channel.closed) return;
    channel.closed = true;
    if (channel._retryTimer) clearTimeout(channel._retryTimer);
    try {
      if (channel.upstreamReq) channel.upstreamReq.destroy();
    } catch {
      /* ignore */
    }
    try {
      if (channel.upstreamRes) channel.upstreamRes.destroy();
    } catch {
      /* ignore */
    }
    // Termine proprement les réponses clients encore ouvertes.
    for (const sub of channel.subscribers.values()) {
      try {
        sub.res.end();
      } catch {
        /* ignore */
      }
    }
    channel.subscribers.clear();
    this.channels.delete(channel.key);
    this.log.info(
      `Chaîne "${channel.key}" fermée (${why}). Amonts actifs : ${this.activeUpstreams}/${this.config.PROVIDER_MAX_CONNECTIONS}`,
    );
    this.emit('channel-close', { channelKey: channel.key, why });
  }

  /** Recopie les en-têtes amont pertinents vers la réponse d'un client. */
  _applyUpstreamHeaders(res, headers) {
    // On propage surtout le content-type (souvent video/MP2T pour du .ts).
    const ct = headers['content-type'] || 'application/octet-stream';
    try {
      res.setHeader('Content-Type', ct);
      // Flux live : pas de mise en cache, connexion maintenue.
      res.setHeader('Cache-Control', 'no-cache, no-store');
      res.setHeader('Connection', 'keep-alive');
    } catch {
      // headers déjà envoyés : sans gravité.
    }
  }

  /**
   * Balayage de backpressure — appelé périodiquement.
   *
   * Objectif : garantir que la mémoire reste bornée SANS jamais bloquer le flux
   * live des clients sains. On coupe :
   *   1) tout client dont la file dépasse CLIENT_BUFFER_MAX_BYTES (client lent) ;
   *   2) si le cumul global dépasse GLOBAL_CLIENT_BUFFER_MAX_BYTES, on coupe en
   *      priorité les clients les plus en retard jusqu'à repasser sous le plafond.
   * Cette opération est O(N) et ne touche jamais au `_pump` amont.
   */
  _sweepBackpressure() {
    if (this.channels.size === 0) return;

    const perClientCap = this.config.CLIENT_BUFFER_MAX_BYTES;
    const globalCap = this.config.GLOBAL_CLIENT_BUFFER_MAX_BYTES;

    let totalBuffered = 0;
    const all = []; // { channel, sub, buffered } pour un éventuel tri global

    for (const channel of this.channels.values()) {
      for (const sub of channel.subscribers.values()) {
        const buffered = sub.buffered;
        totalBuffered += buffered;

        // (1) Client individuellement trop en retard → on le coupe.
        if (buffered > perClientCap) {
          this.log.warn(
            `Coupe client lent ${sub.id} sur "${channel.key}" : ` +
              `${(buffered / 1024 / 1024).toFixed(1)} Mo tamponnés > cap ${(perClientCap / 1024 / 1024).toFixed(0)} Mo`,
          );
          this._dropSlow(channel, sub);
        } else {
          all.push({ channel, sub, buffered });
        }
      }
    }

    // (2) Plafond global dépassé : on coupe les plus lents d'abord.
    if (totalBuffered > globalCap) {
      this.log.warn(
        `Plafond mémoire global dépassé : ` +
          `${(totalBuffered / 1024 / 1024).toFixed(0)} Mo > ${(globalCap / 1024 / 1024).toFixed(0)} Mo → coupe des plus lents`,
      );
      all.sort((a, b) => b.buffered - a.buffered); // du plus lent au plus rapide
      let running = totalBuffered;
      for (const item of all) {
        if (running <= globalCap) break;
        this._dropSlow(item.channel, item.sub);
        running -= item.buffered;
      }
    }
  }

  /** Coupe brutalement un client lent (destroy) et le retire de sa chaîne. */
  _dropSlow(channel, sub) {
    sub.alive = false;
    try {
      // destroy() vide immédiatement la file du socket → libère la RAM.
      sub.res.destroy();
    } catch {
      /* ignore */
    }
    this._removeSubscriber(channel, sub.id, 'client lent coupé (backpressure)');
    this.emit('drop-slow', { channelKey: channel.key, subId: sub.id });
  }

  /** Statistiques instantanées (exposées via /healthz et utilisées par les tests). */
  stats() {
    const channels = [];
    for (const ch of this.channels.values()) {
      channels.push({
        key: ch.key,
        subscribers: ch.size,
        bytesIn: ch.bytesIn,
        closed: ch.closed,
      });
    }
    return {
      activeUpstreams: this.activeUpstreams,
      providerMax: this.config.PROVIDER_MAX_CONNECTIONS,
      totalSubscribers: this.totalSubscribers,
      broadcastMax: this.config.BROADCAST_MAX_STREAMS,
      totalBufferedBytes: this.totalBuffered,
      globalBufferCap: this.config.GLOBAL_CLIENT_BUFFER_MAX_BYTES,
      channels,
    };
  }

  /** Arrêt propre du hub (ferme tout). */
  close() {
    this.closed = true;
    if (this._sweepTimer) clearInterval(this._sweepTimer);
    for (const channel of [...this.channels.values()]) {
      this._closeChannel(channel, 'arrêt du hub');
    }
  }
}

module.exports = { Hub, Channel, Subscriber, makeLogger };
