// =========================================================
//  realtime.js — Hub temps réel (Durable Object « RealtimeHub »)
// =========================================================
//
//  Couche temps réel du protocole décrit dans docs/REALTIME-PROTOCOL.md.
//  Objectif : qu'une action panel (gel, activation, playlist poussée…)
//  atteigne l'appareil EN MOINS D'UNE SECONDE quand il est en ligne,
//  et que le panel voie EN DIRECT qui est connecté / ce qui est regardé.
//
//  Le polling existant (heartbeat 6 h, sync 5 min) reste le filet de
//  sécurité : tout ici est FAIL-OPEN. Si le hub est indisponible, l'app
//  et le panel se comportent exactement comme avant.
//
//  ARCHITECTURE
//  ────────────
//  - UNE instance unique du Durable Object (`idFromName('hub-v1')`) qui
//    tient TOUS les WebSockets (appareils + panels admin).
//  - API « WebSocket Hibernation » de Cloudflare : quand aucun message ne
//    circule, l'objet est ÉVACUÉ de la mémoire (coût quasi nul au repos)
//    mais les sockets restent ouverts. Au prochain message, le runtime
//    ré-instancie la classe et appelle webSocketMessage(). L'état par
//    socket survit grâce à serializeAttachment()/deserializeAttachment().
//  - Chaque socket est TAGUÉ à l'acceptation (`kind:device`, `kind:admin`,
//    `mac:MK:…`) : après hibernation, `state.getWebSockets(tag)` retrouve
//    instantanément les sockets voulus sans aucune Map mémoire.
//  - `setWebSocketAutoResponse('ping' → 'pong')` répond aux keepalives
//    clients SANS réveiller l'objet (donc sans facturation).
//
//  ROUTES INTERNES (joignables uniquement via le binding env.RT_HUB —
//  jamais exposées directement à Internet, donc pas d'auth ici ; c'est
//  worker.js qui authentifie AVANT de forwarder) :
//    GET  /connect-device  → upgrade WebSocket appareil (query mac/platform/v/b/model)
//    GET  /connect-admin   → upgrade WebSocket panel admin
//    POST /publish         → { targets, event } → diffusion, renvoie { delivered, id }
//
//  SÉCURITÉ / ROBUSTESSE
//    - frames > 8 Ko ignorées ; frames non-JSON ignorées silencieusement ;
//    - le socket appareil ne transporte JAMAIS de credentials : uniquement
//      des ordres « va re-fetcher » (l'app repasse par ses fetchs HTTPS) ;
//    - présence D1 mise à jour en best-effort, throttlée ≥ 30 s par MAC.
// =========================================================

// Regex MAC virtuelle 7 MOTION (même format que worker.js / api_v1.js).
const RT_MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

// Taille max d'une frame entrante (spec §8) — au-delà on ignore.
const MAX_FRAME_BYTES = 8 * 1024;

// Throttle d'écriture présence D1 : au plus une écriture / 30 s / MAC.
const PRESENCE_WRITE_MS = 30 * 1000;

// Génère un id d'évènement court : evt_ab12cd34 (suffisant pour corréler
// un `sync`/`message` avec son `ack`, pas besoin d'un UUID complet).
function genEventId() {
  return 'evt_' + crypto.randomUUID().slice(0, 8);
}

// =========================================================
//  RealtimeHub — le Durable Object
// =========================================================
export class RealtimeHub {
  constructor(state, env) {
    this.state = state;
    this.env = env;

    // Horodatage d'envoi par id d'évènement → sert à calculer latencyMs
    // quand l'appareil renvoie son `ack`. VOLONTAIREMENT en mémoire simple :
    // si l'objet hiberne entre l'envoi et l'ack, on perd l'horodatage et on
    // relaie `latencyMs: null` — acceptable (la latence est purement
    // informative, l'ack lui-même n'est jamais perdu).
    this._sentAt = new Map();

    // Throttle présence : dernière écriture D1 par MAC. Même logique :
    // perdre cette Map à l'hibernation ne coûte qu'une écriture de plus.
    this._lastPresenceWrite = new Map();

    // Drapeau DDL présence (une fois par instanciation, pattern _xReady
    // de worker.js) — la table existe déjà côté heartbeat, ceci n'est
    // qu'un filet pour une base vierge.
    this._presenceReady = false;

    // Keepalive AUTOMATIQUE : le runtime répond « pong » à toute frame
    // texte littérale « ping » SANS réveiller l'objet (gratuit). C'est le
    // keepalive NAT des apps ET des panels (toutes les 45 s côté app).
    try {
      this.state.setWebSocketAutoResponse(
        new WebSocketRequestResponsePair('ping', 'pong'),
      );
    } catch (_) {
      // Runtime trop ancien : les 'ping' arriveront dans webSocketMessage()
      // qui les gère aussi (défense en profondeur, cf. plus bas).
    }
  }

  // -------------------------------------------------------
  //  fetch — routes internes (uniquement via le binding RT_HUB)
  // -------------------------------------------------------
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/connect-device') {
      return this.connectDevice(request, url);
    }
    if (url.pathname === '/connect-admin') {
      return this.connectAdmin(request, url);
    }
    if (url.pathname === '/publish' && request.method === 'POST') {
      return this.publish(request);
    }
    return new Response(JSON.stringify({ error: 'not_found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
    });
  }

  // -------------------------------------------------------
  //  /connect-device — un appareil (app Flutter) se connecte
  // -------------------------------------------------------
  //  worker.js a DÉJÀ validé la MAC, le rate-limit et l'Upgrade avant de
  //  forwarder — on re-vérifie quand même (défense en profondeur : le hub
  //  ne doit jamais accepter un socket sans MAC valide).
  async connectDevice(request, url) {
    if ((request.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') {
      return new Response('expected websocket', { status: 426 });
    }
    const mac = String(url.searchParams.get('mac') || '').trim().toUpperCase();
    if (!RT_MAC_RX.test(mac)) {
      return new Response('invalid mac', { status: 400 });
    }

    const now = Date.now();
    const meta = {
      platform: String(url.searchParams.get('platform') || '').slice(0, 16),
      appVersion: String(url.searchParams.get('v') || '').slice(0, 32),
      appBuild: String(url.searchParams.get('b') || '').slice(0, 16),
      model: String(url.searchParams.get('model') || '').slice(0, 64),
      // IP / pays captés par worker.js (CF-Connecting-IP / CF-IPCountry)
      // et transmis en headers internes — le DO ne voit pas les headers CF.
      country: String(request.headers.get('X-RT-Country') || '').slice(0, 8),
      ip: String(request.headers.get('X-RT-IP') || '').slice(0, 64),
    };

    // UNE connexion par MAC : une nouvelle connexion REMPLACE l'ancienne
    // (spec §2 — l'app a redémarré / changé de réseau ; l'ancien socket est
    // un zombie). L'ancien reçoit bye{replaced} → il sait qu'il ne doit PAS
    // se reconnecter immédiatement (backoff max côté app). On capture la
    // liste MAINTENANT mais on ne ferme qu'APRÈS avoir accepté le nouveau
    // socket : ainsi onSocketGone() voit toujours un socket restant pour
    // cette MAC et n'émet jamais de faux device_offline pendant le relais.
    const replaced = this.state.getWebSockets('mac:' + mac);

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    // acceptWebSocket (et PAS ws.accept()) = mode HIBERNATION : le runtime
    // gère le socket, nous réveille via webSocketMessage/Close/Error, et
    // l'objet peut être évacué de la mémoire sans couper la connexion.
    this.state.acceptWebSocket(server, ['kind:device', 'mac:' + mac]);
    // L'attachment est SÉRIALISÉ par le runtime : il survit à l'hibernation
    // (c'est notre seule « mémoire » fiable par socket).
    server.serializeAttachment({
      kind: 'device',
      mac,
      meta,
      channel: '',
      connectedAt: now,
      lastSeenAt: now,
    });

    // Maintenant que le remplaçant est en place, on congédie les anciens.
    for (const old of replaced) {
      try { old.send(JSON.stringify({ type: 'bye', reason: 'replaced' })); } catch (_) {}
      try { old.close(1000, 'replaced'); } catch (_) {}
    }

    // Les panels connectés voient l'appareil apparaître EN DIRECT.
    this.broadcastToAdmins({
      type: 'device_online',
      device: this.deviceInfo({ kind: 'device', mac, meta, channel: '', connectedAt: now, lastSeenAt: now }),
    });

    return new Response(null, { status: 101, webSocket: client });
  }

  // -------------------------------------------------------
  //  /connect-admin — un panel (React) se connecte
  // -------------------------------------------------------
  //  L'auth JWT a été faite par worker.js AVANT le forward (le hub ne
  //  reçoit que des admins déjà vérifiés, jamais de revendeur).
  async connectAdmin(request) {
    if ((request.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') {
      return new Response('expected websocket', { status: 426 });
    }
    const now = Date.now();

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    this.state.acceptWebSocket(server, ['kind:admin']);
    server.serializeAttachment({
      kind: 'admin',
      mac: null,
      meta: {},
      channel: null,
      connectedAt: now,
      lastSeenAt: now,
    });

    // SNAPSHOT immédiat (spec §3) : l'état complet des appareils en ligne,
    // reconstruit depuis les attachments (fiable même après hibernation).
    try {
      server.send(JSON.stringify({ type: 'snapshot', devices: this.onlineDevices() }));
    } catch (_) { /* le panel re-demandera via sa reconnexion */ }

    return new Response(null, { status: 101, webSocket: client });
  }

  // -------------------------------------------------------
  //  /publish — diffusion interne (Worker → Hub)
  // -------------------------------------------------------
  //  Appelé par publishRt() depuis worker.js / api_v1.js après chaque
  //  mutation. targets: 'admins' | 'all-devices' | ['MK:…', …].
  //  Renvoie { delivered, id } — `delivered` = nb de sockets réellement
  //  touchés (0 → l'appareil est hors ligne, le panel affichera
  //  « sera appliqué à sa prochaine connexion »).
  async publish(request) {
    let payload;
    try { payload = await request.json(); } catch (_) {
      return jsonInternal({ error: 'bad_json' }, 400);
    }
    const targets = payload && payload.targets;
    const event = (payload && payload.event) || {};
    if (!event.type) return jsonInternal({ error: 'bad_event' }, 400);

    // Chaque évènement poussé porte un id court : l'appareil le renvoie
    // dans son `ack`, ce qui permet au panel d'afficher « Appliqué ✓ ».
    if (!event.id) event.id = genEventId();

    // Résolution des sockets cibles via les TAGS (hibernation-proof).
    let sockets = [];
    if (targets === 'admins') {
      sockets = this.state.getWebSockets('kind:admin');
    } else if (targets === 'all-devices') {
      sockets = this.state.getWebSockets('kind:device');
    } else if (Array.isArray(targets)) {
      for (const rawMac of targets) {
        const mac = String(rawMac || '').trim().toUpperCase();
        if (!RT_MAC_RX.test(mac)) continue; // cible invalide → ignorée
        sockets = sockets.concat(this.state.getWebSockets('mac:' + mac));
      }
    } else {
      return jsonInternal({ error: 'bad_targets' }, 400);
    }

    const frame = JSON.stringify(event);
    let delivered = 0;
    for (const ws of sockets) {
      try { ws.send(frame); delivered++; } catch (_) { /* socket mort → ignoré */ }
    }

    // Mémorise l'heure d'envoi pour la latence de l'ack (best-effort).
    this.rememberSentAt(event.id);

    return jsonInternal({ delivered, id: event.id });
  }

  // -------------------------------------------------------
  //  Handlers Hibernation API — messages entrants
  // -------------------------------------------------------
  async webSocketMessage(ws, message) {
    // Frames binaires : jamais utilisées par notre protocole → ignorées.
    if (typeof message !== 'string') return;
    // Garde-fou taille (spec §8) : 8 Ko max, au-delà on ignore.
    if (message.length > MAX_FRAME_BYTES) return;
    // 'ping' littéral : normalement absorbé par setWebSocketAutoResponse
    // SANS réveiller l'objet ; si on arrive quand même ici (vieux runtime),
    // on répond à la main.
    if (message === 'ping') {
      try { ws.send('pong'); } catch (_) {}
      return;
    }

    // Frames non-JSON ignorées SILENCIEUSEMENT (spec §8) — on ne ferme pas
    // le socket : une app boguée ne doit pas perdre son canal temps réel.
    let msg;
    try { msg = JSON.parse(message); } catch (_) { return; }
    if (!msg || typeof msg.type !== 'string') return;

    // L'attachment est notre état par socket (survit à l'hibernation).
    let att;
    try { att = ws.deserializeAttachment(); } catch (_) { att = null; }
    if (!att || !att.kind) return;

    if (att.kind === 'device') return this.onDeviceMessage(ws, att, msg);
    if (att.kind === 'admin') return this.onAdminMessage(ws, att, msg);
  }

  // ----- Messages APPAREIL → hub -----
  async onDeviceMessage(ws, att, msg) {
    const now = Date.now();

    switch (msg.type) {
      // hello : 1re frame après connexion — complète les métadonnées
      // (l'app en sait plus que la query string : chaîne en cours, etc.).
      case 'hello': {
        att.meta = {
          ...att.meta,
          platform: strOr(msg.platform, att.meta.platform, 16),
          appVersion: strOr(msg.appVersion, att.meta.appVersion, 32),
          appBuild: strOr(msg.appBuild, att.meta.appBuild, 16),
          model: strOr(msg.model, att.meta.model, 64),
        };
        att.channel = strOr(msg.channel, att.channel || '', 120);
        att.lastSeenAt = now;
        try { ws.serializeAttachment(att); } catch (_) {}
        // Le panel reçoit la fiche complète (device_online « enrichi »).
        this.broadcastToAdmins({ type: 'device_online', device: this.deviceInfo(att) });
        await this.writePresence(att, now);
        return;
      }

      // watching : changement de chaîne (ou re-annonce toutes les 60 s).
      // '' = l'utilisateur ne regarde rien.
      case 'watching': {
        att.channel = strOr(msg.channel, '', 120);
        att.lastSeenAt = now;
        try { ws.serializeAttachment(att); } catch (_) {}
        this.broadcastToAdmins({ type: 'watching', mac: att.mac, channel: att.channel });
        // Présence D1 throttlée ≥ 30 s / MAC : /api/v1/online, /api/trending
        // et le panneau legacy restent exacts SANS marteler la base.
        await this.writePresence(att, now);
        return;
      }

      // ack : l'appareil confirme avoir appliqué un sync/message reçu.
      // On relaie aux admins avec la latence mesurée (si on a encore
      // l'horodatage d'envoi — sinon null, cf. _sentAt).
      case 'ack': {
        const id = strOr(msg.id, '', 64);
        if (!id) return;
        const sent = this._sentAt.get(id);
        if (sent !== undefined) this._sentAt.delete(id);
        const latencyMs = sent !== undefined ? Math.max(0, now - sent) : null;
        this.broadcastToAdmins({
          type: 'ack',
          id,
          mac: att.mac,
          ok: msg.ok !== false,
          latencyMs,
          ...(msg.error ? { error: strOr(msg.error, '', 200) } : {}),
        });
        return;
      }

      default:
        // Type inconnu : ignoré (compat ascendante — une app plus récente
        // que le hub ne doit pas être déconnectée).
        return;
    }
  }

  // ----- Messages PANEL → hub -----
  async onAdminMessage(ws, att, msg) {
    switch (msg.type) {
      // cmd : le panel adresse UN appareil directement (sync ciblé ou
      // message/bannière in-app). ex. { id, mac, action:'message',
      // payload:{title, body, kind, durationSec} }.
      case 'cmd': {
        const mac = String(msg.mac || '').trim().toUpperCase();
        if (!RT_MAC_RX.test(mac)) return;
        const id = strOr(msg.id, '', 64) || genEventId();
        let event = null;
        if (msg.action === 'sync') {
          const what = ['status', 'sources', 'config', 'all']
            .includes(msg.payload && msg.payload.what) ? msg.payload.what : 'all';
          event = { type: 'sync', what, id };
        } else if (msg.action === 'message') {
          const p = msg.payload || {};
          event = {
            type: 'message',
            id,
            title: strOr(p.title, '', 80),
            body: strOr(p.body, '', 500),
            kind: ['info', 'success', 'warning'].includes(p.kind) ? p.kind : 'info',
            ...(Number(p.durationSec) > 0 ? { durationSec: Number(p.durationSec) } : {}),
          };
        }
        if (!event) return;
        const frame = JSON.stringify(event);
        let delivered = 0;
        for (const target of this.state.getWebSockets('mac:' + mac)) {
          try { target.send(frame); delivered++; } catch (_) {}
        }
        this.rememberSentAt(id);
        // Retour immédiat à L'ÉMETTEUR : delivered=0 → « appareil hors
        // ligne » affichable tout de suite (l'ack, lui, viendra du device).
        try { ws.send(JSON.stringify({ type: 'cmd_sent', id, mac, delivered })); } catch (_) {}
        return;
      }
      default:
        return; // types inconnus ignorés
    }
  }

  // -------------------------------------------------------
  //  Handlers Hibernation API — fermeture / erreur
  // -------------------------------------------------------
  async webSocketClose(ws, _code, _reason, _wasClean) {
    await this.onSocketGone(ws);
  }

  async webSocketError(ws, _error) {
    await this.onSocketGone(ws);
  }

  //  Un socket disparaît (close propre ou erreur réseau). Pour un appareil,
  //  on prévient les panels — SAUF si un autre socket existe encore pour la
  //  même MAC (cas « remplacé » : la nouvelle connexion a déjà pris le
  //  relais, annoncer offline serait un faux négatif).
  async onSocketGone(ws) {
    let att;
    try { att = ws.deserializeAttachment(); } catch (_) { att = null; }
    if (!att || att.kind !== 'device' || !att.mac) return;

    const remaining = this.state.getWebSockets('mac:' + att.mac)
      .filter((s) => s !== ws);
    if (remaining.length > 0) return; // remplacé → toujours en ligne

    const now = Date.now();
    this.broadcastToAdmins({ type: 'device_offline', mac: att.mac, at: now });
    // Dernière trace de présence (non throttlée : c'est LA fraîcheur finale
    // qu'exploiteront /api/v1/online et le heartbeat de compat).
    await this.writePresence(att, now, /*force=*/true);
  }

  // -------------------------------------------------------
  //  Helpers internes
  // -------------------------------------------------------

  /// Fiche appareil au format snapshot/device_online (spec §3).
  deviceInfo(att) {
    const m = att.meta || {};
    return {
      mac: att.mac,
      platform: m.platform || '',
      country: m.country || '',
      channel: att.channel || '',
      appVersion: m.appVersion || '',
      model: m.model || '',
      connectedAt: att.connectedAt || 0,
      lastSeen: att.lastSeenAt || 0,
    };
  }

  /// Liste des appareils actuellement connectés (via tags + attachments —
  /// AUCUNE Map mémoire, donc exact même juste après une hibernation).
  onlineDevices() {
    const out = [];
    const seen = new Set(); // dédoublonne l'instant précis d'un remplacement
    // MODE ADMIN MONITORING : on exclut les MAC maîtres/admin de la liste
    // « live » envoyée aux panels clients (set cache alimenté par _isAdminMac).
    const admins = (this._masterCache && this._masterCache.set) || null;
    for (const ws of this.state.getWebSockets('kind:device')) {
      let att;
      try { att = ws.deserializeAttachment(); } catch (_) { continue; }
      if (!att || !att.mac || seen.has(att.mac)) continue;
      if (admins && admins.has(String(att.mac).toUpperCase())) continue;
      seen.add(att.mac);
      out.push(this.deviceInfo(att));
    }
    return out;
  }

  /// Envoie un évènement JSON à TOUS les panels connectés (best-effort).
  broadcastToAdmins(event) {
    let frame;
    try { frame = JSON.stringify(event); } catch (_) { return; }
    for (const ws of this.state.getWebSockets('kind:admin')) {
      try { ws.send(frame); } catch (_) { /* panel déconnecté → ignoré */ }
    }
  }

  /// Retient l'heure d'envoi d'un évènement (pour latencyMs de l'ack),
  /// avec un plafond dur pour ne jamais gonfler la mémoire de l'objet.
  rememberSentAt(id) {
    if (!id) return;
    this._sentAt.set(id, Date.now());
    if (this._sentAt.size > 500) {
      // On élague les plus anciens (ordre d'insertion des Map JS).
      const drop = this._sentAt.size - 400;
      let i = 0;
      for (const k of this._sentAt.keys()) {
        if (i++ >= drop) break;
        this._sentAt.delete(k);
      }
    }
  }

  /// Écrit la présence dans D1 (table `presence` partagée avec le
  /// heartbeat HTTP) — best-effort, throttlé ≥ 30 s par MAC sauf `force`.
  /// FAIL-OPEN : un pépin D1 ne doit JAMAIS toucher au canal temps réel.
  async writePresence(att, now, force = false) {
    if (!this.env || !this.env.DB || !att || !att.mac) return;
    const last = this._lastPresenceWrite.get(att.mac) || 0;
    if (!force && now - last < PRESENCE_WRITE_MS) return;
    this._lastPresenceWrite.set(att.mac, now);
    try {
      if (!this._presenceReady) {
        // Même DDL idempotent que recordPresence() de worker.js — filet
        // pour une base vierge, exécuté UNE fois par instanciation.
        // Les DEUX index aussi : si le hub crée la table AVANT le premier
        // heartbeat HTTP, les agrégations /online et /trending feraient
        // sinon des full scans jusqu'à ce que worker.js les ajoute.
        await this.env.DB.prepare(
          'CREATE TABLE IF NOT EXISTS presence (' +
            'mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT)'
        ).run();
        try {
          await this.env.DB.prepare(
            'CREATE INDEX IF NOT EXISTS idx_presence_lastseen ON presence(last_seen)'
          ).run();
          await this.env.DB.prepare(
            'CREATE INDEX IF NOT EXISTS idx_presence_channel ON presence(channel)'
          ).run();
        } catch (_) { /* index best-effort */ }
        this._presenceReady = true;
      }
      const m = att.meta || {};
      // MODE ADMIN MONITORING : une MAC maître/admin ne pollue pas la table
      // `presence` (stats clients). Sa présence part dans `admin_presence`.
      const table = (await this._isAdminMac(att.mac)) ? 'admin_presence' : 'presence';
      if (table === 'admin_presence') {
        try {
          await this.env.DB.prepare(
            'CREATE TABLE IF NOT EXISTS admin_presence (' +
              'mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT)'
          ).run();
        } catch (_) { /* déjà là */ }
        try { await this.env.DB.prepare('DELETE FROM presence WHERE mac = ?').bind(att.mac).run(); } catch (_) {}
      }
      await this.env.DB.prepare(
        'INSERT INTO ' + table + ' (mac, ip, country, last_seen, channel) VALUES (?, ?, ?, ?, ?) ' +
          'ON CONFLICT(mac) DO UPDATE SET ip = excluded.ip, ' +
          'country = excluded.country, last_seen = excluded.last_seen, channel = excluded.channel'
      ).bind(att.mac, m.ip || null, m.country || null, now,
             String(att.channel || '').slice(0, 120)).run();
    } catch (_) {
      // best-effort : la présence ne casse jamais le temps réel.
    }
  }

  /// Cette MAC est-elle un compte maître/admin ? (cache mémoire 60 s pour ne
  /// pas requêter app_masters à chaque écriture de présence). FAIL-OPEN : en
  /// cas de doute → false (présence cliente normale).
  async _isAdminMac(mac) {
    const key = String(mac || '').toUpperCase();
    const now = Date.now();
    if (!this._masterCache || now - this._masterCache.at > 60_000) {
      let set = new Set();
      try {
        const rs = await this.env.DB.prepare('SELECT mac FROM app_masters').all();
        set = new Set(((rs && rs.results) || []).map((r) => String(r.mac).toUpperCase()));
      } catch (_) { /* table absente → aucun admin */ }
      this._masterCache = { at: now, set };
    }
    return this._masterCache.set.has(key);
  }
}

// Réponse JSON minimaliste pour les routes internes du DO (pas de CORS :
// ces routes ne sont joignables que via le binding, jamais un navigateur).
function jsonInternal(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

/// Coercition champ texte : valeur si string non vide, sinon fallback.
function strOr(v, fallback, maxLen) {
  const s = typeof v === 'string' ? v : (v === 0 ? '0' : '');
  const out = s !== '' ? s : (fallback || '');
  return String(out).slice(0, maxLen);
}

// =========================================================
//  Helpers exportés — appelables depuis worker.js / api_v1.js
// =========================================================

/// `true` si le binding Durable Object est déployé (wrangler.toml
/// [durable_objects] + migration). Absent → les routes rt renvoient 503
/// et les publications sont des no-op silencieux.
export function rtAvailable(env) {
  return !!(env && env.RT_HUB);
}

/// Publie un évènement via le hub — TOUJOURS FAIL-OPEN (spec §4).
///   publishRt(env, { targets, event })
///   targets : 'admins' | 'all-devices' | ['MK:…', …]
///   event   : { type: 'sync'|'message'|'changed'|…, … }
///   Retour  : { delivered, id } — jamais d'exception remontée : si le hub
///             est absent/planté, on renvoie { delivered: 0, id: null } et
///             la mutation HTTP appelante continue comme si de rien n'était
///             (le polling existant fera foi).
export async function publishRt(env, { targets, event } = {}) {
  if (!rtAvailable(env)) return { delivered: 0, id: null };
  try {
    const stub = env.RT_HUB.get(env.RT_HUB.idFromName('hub-v1'));
    // Hôte factice : seul le pathname compte pour le fetch interne du DO.
    const res = await stub.fetch('https://rt-hub.internal/publish', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ targets, event }),
    });
    if (!res.ok) return { delivered: 0, id: null };
    const out = await res.json();
    return {
      delivered: Number(out && out.delivered) || 0,
      id: (out && out.id) || null,
    };
  } catch (_) {
    return { delivered: 0, id: null }; // fail-open, toujours.
  }
}
