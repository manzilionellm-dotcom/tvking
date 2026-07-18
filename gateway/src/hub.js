// =========================================================
//  hub.js — Multiplexeur de flux (mutualisation des flux IDENTIQUES)
// =========================================================
//  Règle d'or (honnête, sans contournement) :
//   • Une chaîne = une clé. Le PREMIER spectateur ouvre UNE connexion vers
//     le fournisseur. Les spectateurs SUIVANTS de la MÊME chaîne se
//     branchent sur ce flux unique (0 connexion fournisseur en plus).
//   • Des chaînes DIFFÉRENTES = des connexions différentes. On n'invente
//     rien : 5 chaînes distinctes = 5 connexions upstream.
//   • Le nombre de connexions upstream DISTINCTES ne dépasse jamais
//     PROVIDER_MAX_CONNECTIONS → protège la ligne d'un bannissement.
//
//  Robustesse : reconnexion upstream avec backoff, coupure des clients trop
//  lents (protège les autres), fermeture différée quand plus personne ne
//  regarde (zapping aller-retour fluide).
// =========================================================
import { openStream } from './upstream.js';
import { config } from './config.js';
import { metrics } from './metrics.js';
import { log } from './logger.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class StreamSession {
  constructor(hub, key, url) {
    this.hub = hub;
    this.key = key;
    this.url = url;
    this.subscribers = new Set(); // Set<ServerResponse>
    this.abort = new AbortController();
    this.state = 'connecting'; // connecting | live | reconnecting | closed
    this.upstreamStatus = 0;
    this.contentType = 'video/mp2t';
    this.bytesIn = 0;
    this.startedAt = Date.now();
    this.idleTimer = null;
    this.closed = false;
    // Promesse résolue quand la 1re connexion upstream a un verdict.
    this.ready = this._connectLoop();
  }

  // ---- Connexion + boucle de reconnexion --------------------------------
  async _connectLoop() {
    let attempt = 0;
    for (;;) {
      if (this.closed) return false;
      try {
        const res = await openStream(this.url, this.abort.signal);
        this.upstreamStatus = res.statusCode;
        if (res.statusCode >= 400) {
          // Échec DÉFINITIF côté fournisseur (auth, chaîne morte…) : on ne
          // mutualise pas une erreur, on remonte le statut aux clients.
          try { res.body.destroy(); } catch { /* ignore */ }
          if (attempt === 0) return false; // 1re tentative : verdict d'échec
          // En reconnexion : un 4xx définitif → on abandonne.
          this._endAll();
          this._destroy();
          return false;
        }
        this.contentType =
          (res.headers && (res.headers['content-type'] || res.headers['Content-Type'])) ||
          this.contentType;
        if (this.state === 'connecting') {
          metrics.inc('gw_upstream_connects_total');
        } else {
          metrics.inc('gw_upstream_reconnects_total');
        }
        this.state = 'live';
        attempt = 0;
        this._flushHeaders();
        const done = await this._pump(res.body);
        if (done === 'closed') return true; // fermeture volontaire
        // Fin/erreur inattendue d'un flux LIVE → on tente de reconnecter.
        this.state = 'reconnecting';
      } catch (e) {
        if (this.closed) return false;
        this.upstreamStatus = this.upstreamStatus || 0;
        metrics.inc('gw_upstream_errors_total');
        log.warn('upstream.error', { key: this.key, error: String(e && e.message || e) });
        this.state = 'reconnecting';
      }
      // Plus de spectateurs pendant la coupure → inutile de reconnecter.
      if (this.subscribers.size === 0) { this._destroy(); return true; }
      attempt += 1;
      if (attempt > config.upstreamRetries) {
        log.warn('upstream.give_up', { key: this.key, attempts: attempt });
        this._endAll();
        this._destroy();
        return false;
      }
      const backoff = Math.min(
        config.upstreamRetryBaseMs * 2 ** (attempt - 1),
        10_000,
      );
      await sleep(backoff);
    }
  }

  // Diffuse les octets upstream vers tous les abonnés. Résout 'closed' si la
  // session a été fermée volontairement, sinon undefined (fin inattendue).
  _pump(body) {
    return new Promise((resolve) => {
      const onData = (chunk) => {
        this.bytesIn += chunk.length;
        metrics.inc('gw_bytes_upstream_total', chunk.length);
        for (const res of this.subscribers) this._writeTo(res, chunk);
      };
      const cleanup = () => {
        body.removeListener('data', onData);
        body.removeListener('end', onEnd);
        body.removeListener('error', onErr);
      };
      const onEnd = () => { cleanup(); resolve(this.closed ? 'closed' : undefined); };
      const onErr = () => { cleanup(); try { body.destroy(); } catch { /* */ } resolve(this.closed ? 'closed' : undefined); };
      body.on('data', onData);
      body.on('end', onEnd);
      body.on('error', onErr);
    });
  }

  _writeTo(res, chunk) {
    if (res.writableEnded || res.destroyed) return;
    try {
      res.write(chunk);
      metrics.inc('gw_bytes_clients_total', chunk.length);
      // Client trop lent : sa file d'attente enfle → on le coupe pour ne
      // pas retenir tout le monde (le live doit rester temps réel).
      if (res.writableLength > config.clientBufferMaxBytes) {
        log.warn('client.too_slow', { key: this.key });
        this.removeSubscriber(res);
        try { res.destroy(); } catch { /* */ }
      }
    } catch {
      this.removeSubscriber(res);
    }
  }

  _flushHeaders() {
    for (const res of this.subscribers) this._sendHeaders(res);
  }

  _sendHeaders(res) {
    if (res.headersSent || res.writableEnded || res.destroyed) return;
    try {
      res.writeHead(200, {
        'content-type': this.contentType,
        'cache-control': 'no-cache, no-store',
        connection: 'close',
      });
    } catch { /* course : ignore */ }
  }

  // ---- Abonnés -----------------------------------------------------------
  addSubscriber(res) {
    this.subscribers.add(res);
    metrics.addGauge('gw_clients_active', 1);
    if (this.idleTimer) { clearTimeout(this.idleTimer); this.idleTimer = null; }
    // Déjà en direct : on envoie les en-têtes tout de suite, le flux suit.
    if (this.state === 'live') this._sendHeaders(res);
    const onClose = () => this.removeSubscriber(res);
    res.on('close', onClose);
    res._gwOnClose = onClose;
  }

  removeSubscriber(res) {
    if (!this.subscribers.has(res)) return;
    this.subscribers.delete(res);
    metrics.addGauge('gw_clients_active', -1);
    if (res._gwOnClose) { res.removeListener('close', res._gwOnClose); res._gwOnClose = null; }
    if (this.subscribers.size === 0 && !this.closed) this._armIdle();
  }

  _armIdle() {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      if (this.subscribers.size === 0) {
        log.info('session.idle_close', { key: this.key });
        this._destroy();
      }
    }, config.streamIdleGraceMs);
    if (this.idleTimer.unref) this.idleTimer.unref();
  }

  _endAll() {
    for (const res of [...this.subscribers]) {
      this.removeSubscriber(res);
      try { res.end(); } catch { /* */ }
    }
  }

  _destroy() {
    if (this.closed) return;
    this.closed = true;
    this.state = 'closed';
    if (this.idleTimer) { clearTimeout(this.idleTimer); this.idleTimer = null; }
    try { this.abort.abort(); } catch { /* */ }
    this.hub._remove(this.key);
  }

  info() {
    return {
      key: this.key,
      state: this.state,
      subscribers: this.subscribers.size,
      upstreamStatus: this.upstreamStatus,
      bytesIn: this.bytesIn,
      sinceMs: Date.now() - this.startedAt,
    };
  }
}

export class StreamHub {
  constructor() {
    this.sessions = new Map(); // key -> StreamSession (live mutualisé)
    this.rawSlots = 0;         // connexions VOD (non mutualisées) en cours
    this._sweepTimer = null;   // ronde anti-backpressure (plafond mémoire global)
  }

  // Connexions upstream DISTINCTES au total (= ce que voit le fournisseur) :
  // les sessions live mutualisées + les flux VOD directs.
  totalUpstream() { return this.sessions.size + this.rawSlots; }

  _remove(key) {
    this.sessions.delete(key);
    metrics.setGauge('gw_upstream_active', this.totalUpstream());
  }

  /**
   * Ferme UNE session en « idle-grace » (plus aucun spectateur, connexion
   * gardée au chaud quelques secondes pour un zapping aller-retour fluide)
   * afin de libérer un slot fournisseur pour une nouvelle chaîne. On ferme
   * AVANT d'ouvrir : la limite fournisseur n'est jamais dépassée. Évite le
   * 503 sur un zapping normal quand la ligne est « pleine » de sessions qui
   * n'ont en réalité plus personne devant l'écran.
   * @returns {boolean} true si un slot a été récupéré.
   */
  _reclaimIdleSlot() {
    for (const s of this.sessions.values()) {
      if (!s.closed && s.subscribers.size === 0) {
        log.info('session.reclaim_idle', { key: s.key });
        s._destroy(); // décrémente sessions.size de façon synchrone
        metrics.inc('gw_reclaimed_idle_total');
        return true;
      }
    }
    return false;
  }

  // ---- Plafond mémoire GLOBAL (anti-OOM du process 512 Mo) ---------------
  startBackpressureSweep() {
    if (this._sweepTimer) return;
    if (config.globalClientBufferMaxBytes <= 0 || config.backpressureSweepMs <= 0) return;
    this._sweepTimer = setInterval(() => {
      try { this._sweepBackpressure(); } catch { /* jamais faire tomber la ronde */ }
    }, config.backpressureSweepMs);
    if (this._sweepTimer.unref) this._sweepTimer.unref();
  }

  stopBackpressureSweep() {
    if (this._sweepTimer) { clearInterval(this._sweepTimer); this._sweepTimer = null; }
  }

  // Somme les files d'attente (writableLength) de TOUS les abonnés live ; si le
  // total dépasse le plafond global, coupe les plus lents jusqu'à repasser
  // dessous. Le pipe VOD s'auto-régule (pause upstream), donc non concerné.
  _sweepBackpressure() {
    const cap = config.globalClientBufferMaxBytes;
    if (cap <= 0) return;
    const all = [];
    let total = 0;
    for (const s of this.sessions.values()) {
      for (const res of s.subscribers) {
        const q = res.writableLength || 0;
        total += q;
        all.push({ s, res, q });
      }
    }
    metrics.setGauge('gw_client_buffered_bytes', total);
    if (total <= cap) return;
    all.sort((a, b) => b.q - a.q);
    for (const item of all) {
      if (total <= cap) break;
      log.warn('client.global_backpressure', { key: item.s.key, queuedBytes: item.q });
      item.s.removeSubscriber(item.res);
      try { item.res.destroy(); } catch { /* */ }
      metrics.inc('gw_clients_cut_backpressure_total');
      total -= item.q;
    }
  }

  /**
   * Réserve une connexion fournisseur pour un flux NON mutualisé (VOD/série),
   * dans la limite de la ligne. Renvoie une fonction de libération, ou null
   * si la ligne est déjà pleine.
   */
  reserveRaw() {
    if (this.totalUpstream() >= config.providerMaxConnections) {
      // Ligne « pleine » : on tente de récupérer un slot laissé au chaud pour
      // le zapping (aucun spectateur) avant de refuser.
      if (!this._reclaimIdleSlot() || this.totalUpstream() >= config.providerMaxConnections) {
        metrics.inc('gw_rejected_provider_limit_total');
        return null;
      }
    }
    this.rawSlots += 1;
    metrics.setGauge('gw_upstream_active', this.totalUpstream());
    let done = false;
    return () => {
      if (done) return;
      done = true;
      this.rawSlots = Math.max(0, this.rawSlots - 1);
      metrics.setGauge('gw_upstream_active', this.totalUpstream());
    };
  }

  /**
   * Abonne un client à une chaîne. Mutualise si la chaîne est déjà diffusée.
   * @returns {Promise<{ ok: true } | { ok: false, code: string, status?: number }>}
   */
  async subscribe(key, url, res) {
    let session = this.sessions.get(key);
    if (!session) {
      // Nouvelle chaîne → nouvelle connexion fournisseur : on vérifie la
      // limite AVANT d'ouvrir (jamais dépasser la ligne). Si elle est pleine,
      // on récupère d'abord un slot en idle-grace (zapping) plutôt que refuser.
      if (this.totalUpstream() >= config.providerMaxConnections) {
        if (!this._reclaimIdleSlot() || this.totalUpstream() >= config.providerMaxConnections) {
          metrics.inc('gw_rejected_provider_limit_total');
          return { ok: false, code: 'provider_limit', status: 503 };
        }
      }
      session = new StreamSession(this, key, url);
      this.sessions.set(key, session);
      metrics.setGauge('gw_upstream_active', this.totalUpstream());
      // On attache le client tout de suite : s'il coupe pendant la connexion,
      // la session se fermera d'elle-même (plus d'abonné).
      session.addSubscriber(res);
      const ok = await session.ready.catch(() => false);
      if (!ok) {
        const status = session.upstreamStatus >= 400 ? session.upstreamStatus : 502;
        session._destroy(); // nettoie la session morte + libère le créneau
        return {
          ok: false,
          code: status >= 400 && status < 500 ? 'upstream_error' : 'upstream_unavailable',
          status,
        };
      }
      return { ok: true };
    }
    // Chaîne déjà diffusée → on se branche, 0 connexion fournisseur en plus.
    metrics.inc('gw_mux_join_total');
    session.addSubscriber(res);
    if (session.state !== 'live') {
      const ok = await session.ready.catch(() => false);
      if (!ok) {
        session.removeSubscriber(res);
        return { ok: false, code: 'upstream_unavailable', status: 502 };
      }
    }
    return { ok: true };
  }

  status() {
    return {
      upstreamActive: this.totalUpstream(),
      liveSessions: this.sessions.size,
      vodSessions: this.rawSlots,
      providerMax: config.providerMaxConnections,
      sessions: [...this.sessions.values()].map((s) => s.info()),
    };
  }

  closeAll() {
    for (const s of [...this.sessions.values()]) s._destroy();
  }
}

export const hub = new StreamHub();
