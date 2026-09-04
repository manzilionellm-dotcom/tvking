// =========================================================
//  cast_receiver.js — Custom CAF Web Receiver 7 MOTION / Red Room
// =========================================================
//  Exposee par worker.js sur la route GET /cast-receiver.
//  URL publique a coller dans la Google Cast SDK Developer
//  Console pour obtenir un Receiver Application ID (custom).
//
//  POURQUOI UN CUSTOM RECEIVER (et pas le Default Media Receiver
//  public CC1AD845) :
//    Le Default Media Receiver de Google ne decode PAS le MPEG-TS
//    brut (`video/mp2t`) des flux IPTV Xtream `/live/.../id.ts` :
//    la TV affiche l'ecran "cast" SANS image (constate SHIELD, LG,
//    Samsung). Pour le contourner, l'ancien sender wrappait le .ts
//    en HLS servi par le SERVEUR LOCAL DU TELEPHONE → la TV tirait
//    le flux depuis le telephone → eteindre le telephone COUPAIT la
//    lecture. Le comportement "je caste, j'eteins le tel, la TV joue
//    1-2h" etait donc casse sur toutes les TV modernes.
//
//    Ce custom receiver decode le MPEG-TS LUI-MEME, sur la TV
//    (mpegts.js → transmux TS->fMP4 via Media Source Extensions).
//    Du coup le sender envoie l'URL Xtream DIRECTE : la Chromecast /
//    Google TV fetch le flux directement depuis le serveur IPTV, le
//    telephone n'est plus dans la boucle → on peut l'eteindre, la TV
//    continue. C'est ca, le "cast evolutif".
//
//  ARCHITECTURE :
//    - Page HTML autonome, hebergee par notre Worker (zero backend).
//    - Charge le CAF Receiver SDK v3 + mpegts.js + hls.js (CDN).
//    - <cast-media-player> gere nativement HLS / DASH / MP4 (Shaka).
//    - Un LOAD interceptor route le flux selon son type :
//        * .m3u8  → HLS natif CAF (+ streamType LIVE si live)
//        * .ts / video/mp2t / Xtream /live/ → mpegts.js sur un
//          <video> dedie (le seul chemin fiable pour le TS brut)
//        * mp4/mkv/webm → lecteur natif CAF
//    - mpegts.js ne tourne QUE pour le TS brut ; tout le reste passe
//      par le pipeline CAF standard. 100% additif.
//
//  BRANDING : ?app=redroom bascule le velours / R rouge. La Console
//  Google accepte les query strings, donc 7 MOTION et Red Room ont
//  chacun leur Application ID pointant sur la meme page avec le bon
//  query param.
//
//  REFERENCES :
//    https://developers.google.com/cast/docs/web_receiver/basic
//    https://developers.google.com/cast/docs/media/streaming_protocols
//    https://github.com/xqq/mpegts.js
// =========================================================

export function castReceiverHtml(flavor) {
  // Par defaut : The Few (grand public). ?app=redroom → Privé (adulte).
  // Le query param reste (compat Cast Console) ; seul l'affichage change.
  const isRedRoom = flavor === 'redroom';
  const appName = isRedRoom ? 'Privé' : 'The Few';
  const accent = '#D63A30'; // ember partage
  const bg = isRedRoom ? '#08060A' : '#0A0A0C';
  const logoUrl = isRedRoom
    ? 'https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_redroom.png'
    : 'https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg';

  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${appName} · Cast</title>
  <!--
    CAF Receiver SDK v3 (Cast Application Framework) — transforme la
    page en receiver Cast officiel. mpegts.js = transmux MPEG-TS brut
    (IPTV Xtream) vers fMP4 cote TV. hls.js = repli HLS si le pipeline
    natif CAF refuse une variante. Les deux sont charges depuis un CDN
    par la TV elle-meme (pas par notre backend).
  -->
  <script src="//www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js"></script>
  <!-- mpegts.js servi en MEME ORIGINE par le Worker (/vendor/mpegts.js,
       cache edge). Un CDN tiers (jsdelivr) bloqué/lent sur le réseau de
       la TV cassait TOUT le chemin TS ; le repli CDN ne sert que si notre
       route vendor est indisponible. -->
  <script src="/vendor/mpegts.js"></script>
  <script>
    if (!window.mpegts) {
      document.write('<scr' + 'ipt src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"><\\/scr' + 'ipt>');
    }
  </script>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: ${bg};
      color: #F2F2F4;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }

    /* ===== <cast-media-player> : pipeline CAF natif (HLS/DASH/MP4) ===== */
    cast-media-player {
      --theme-hue: 0;
      --background-color: ${bg};
      --logo-image: url('${logoUrl}');
      --logo-background-color: ${bg};
      --splash-image: url('${logoUrl}');
      --splash-background-color: ${bg};
      --progress-color: ${accent};
      --break-color: ${accent};
      --play-icon-color: #F2F2F4;
      --buffer-color: rgba(255, 90, 74, 0.45);
      width: 100%;
      height: 100%;
    }

    /* ===== <video> dedie au MPEG-TS brut pilote par mpegts.js =====
       Masque par defaut ; on l'affiche PAR-DESSUS le cast-media-player
       uniquement pendant une lecture TS. */
    #ts-video {
      position: fixed;
      inset: 0;
      width: 100%;
      height: 100%;
      background: ${bg};
      object-fit: contain;
      z-index: 1;
      display: none;
    }
    #ts-video.active { display: block; }

    /* ===== Watermark coin bas-droite pendant la lecture ===== */
    .brand-watermark {
      position: fixed;
      right: 24px;
      bottom: 24px;
      z-index: 3;
      opacity: 0.55;
      pointer-events: none;
      font-size: 11px;
      letter-spacing: 3px;
      font-weight: 700;
      color: rgba(255, 255, 255, 0.85);
      text-shadow: 0 2px 8px rgba(0, 0, 0, 0.8);
    }
    .brand-watermark::before {
      content: '';
      display: inline-block;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: ${accent};
      margin-right: 8px;
      vertical-align: middle;
    }

    /* ===== Overlay DEBUG (active via customData {debug:true}) ===== */
    #dbg-overlay {
      position: fixed;
      top: 12px;
      left: 12px;
      max-width: 60%;
      z-index: 99999;
      font-family: "Courier New", Consolas, monospace;
      font-size: 20px;
      line-height: 1.3;
      color: #00FF66;
      text-shadow: 0 0 2px #000, 0 0 2px #000;
      background: rgba(0,0,0,0.45);
      padding: 8px 10px;
      border-radius: 6px;
      white-space: pre-wrap;
      word-break: break-all;
      pointer-events: none;
      display: none;
    }
    #dbg-overlay.active { display: block; }
  </style>
</head>
<body>
  <!-- Pipeline CAF natif : splash + lecture HLS/DASH/MP4. -->
  <cast-media-player></cast-media-player>

  <!-- Element dedie au MPEG-TS brut (mpegts.js). Affiche par-dessus
       le cast-media-player seulement pendant une lecture TS. -->
  <video id="ts-video" playsinline></video>

  <div class="brand-watermark">${appName}</div>

  <!-- Overlay DEBUG (n'apparait que si customData {debug:true} dans le LOAD). -->
  <div id="dbg-overlay"></div>

  <script>
    // =====================================================
    //  Boot du receiver
    // =====================================================
    const APP = '${appName}';
    const context = cast.framework.CastReceiverContext.getInstance();
    const playerManager = context.getPlayerManager();

    const tsVideo = document.getElementById('ts-video');
    let mpegtsPlayer = null;     // instance mpegts.js courante
    let tsActive = false;        // true tant qu'une lecture TS est en cours

    // ---- Etat "custom player" expose aux senders --------------------
    //  QUAND mpegts.js joue (pipeline CAF suspendu par le LOAD
    //  interceptor qui retourne null), CAF ne sait RIEN de la lecture :
    //  sans le plumbing ci-dessous, le telephone ne recevait JAMAIS de
    //  MediaStatus → RemoteMediaClient.load() restait sans reponse, le
    //  sender declarait "echec" a 25 s ALORS QUE LA TV JOUAIT, et
    //  pause/stop depuis le telephone etaient morts (pas de media
    //  session cote sender). Pattern officiel "custom player" : on
    //  reecrit le MEDIA_STATUS sortant + broadcastStatus() a chaque
    //  transition, avec le requestId pour acquitter la commande.
    //  cf. cast.framework.PlayerManager#broadcastStatus /
    //      #setMessageInterceptor (MessageType.MEDIA_STATUS).
    let tsMedia = null;          // MediaInformation du LOAD en cours
    let tsUrl = null;            // URL relancable (reconnexion auto)
    let tsBuffering = false;     // etat BUFFERING expose au sender
    let tsErrorPending = false;  // le prochain status = IDLE/ERROR
    let tsReconnects = 0;        // tentatives de reconnexion consecutives
    let tsReconnectTimer = null;
    const TS_MEDIA_SESSION_ID = 1;   // constant : une seule session TS a la fois
    const TS_MAX_RECONNECTS = 6;     // ~21 s de backoff cumule avant abandon

    function tsBroadcast(requestId) {
      try {
        playerManager.broadcastStatus(true, requestId || undefined);
      } catch (e) { log('broadcastStatus failed', e); }
    }

    // ---- Helpers -------------------------------------------------
    function log() {
      try { console.log.apply(console, ['[' + APP + ' cast]'].concat([].slice.call(arguments))); } catch (e) {}
    }

    // ---- Overlay DEBUG (coin haut-gauche, 15 dernieres lignes) -----
    // Active par customData {debug:true} dans le LOAD, ou par ?debug=1
    // sur l'URL du receiver. N'affiche RIEN en fonctionnement normal.
    let DEBUG = false;
    try { DEBUG = new URLSearchParams(location.search).get('debug') === '1'; } catch (e) {}
    const dbgLines = [];
    const dbgEl = document.getElementById('dbg-overlay');
    function dbgRender() {
      if (!dbgEl) return;
      if (DEBUG) { dbgEl.classList.add('active'); } else { dbgEl.classList.remove('active'); return; }
      // ⚠️ Ce fichier est un TEMPLATE LITERAL : tout backslash destine
      // a la page generee doit etre DOUBLE dans la source. Un backslash
      // simple suivi de n devenait un VRAI retour a la ligne dans le
      // string genere → SyntaxError → TOUT le script receiver mourait
      // au parsing (la TV ne demarrait jamais le CAF, aucune session
      // possible). Bug constate et corrige le 2026-07-05.
      dbgEl.textContent = dbgLines.slice(-15).join('\\n');
    }
    function dbg() {
      const msg = [].slice.call(arguments).map(function (a) {
        if (a && typeof a === 'object') { try { return JSON.stringify(a); } catch (e) { return String(a); } }
        return String(a);
      }).join(' ');
      const t = new Date().toISOString().slice(11, 19);
      dbgLines.push(t + '  ' + msg);
      if (dbgLines.length > 60) dbgLines.shift();
      log(msg);
      dbgRender();
    }
    function dbgSetEnabled(on) { DEBUG = DEBUG || !!on; dbgRender(); }

    // Heuristique : URL de flux MPEG-TS brut (IPTV Xtream live).
    //   - extension .ts (eventuellement suivie de query string)
    //   - contentType video/mp2t
    //   - chemin Xtream /live/USER/PASS/ID(.ts)
    // On EXCLUT explicitement le HLS (.m3u8) qui contient aussi des
    // segments .ts mais doit passer par le pipeline HLS, pas mpegts.js.
    function isRawMpegTs(url, contentType) {
      const u = (url || '').toLowerCase();
      const ct = (contentType || '').toLowerCase();
      if (u.indexOf('.m3u8') !== -1) return false;
      if (ct.indexOf('mpegurl') !== -1) return false;
      if (ct === 'video/mp2t' || ct === 'video/mpeg' || ct === 'video/vnd.dlna.mpeg-tts') return true;
      if (/\\.ts(\\?|$)/.test(u)) return true;
      if (u.indexOf('/live/') !== -1) return true;
      return false;
    }

    // Demonte UNIQUEMENT le moteur mpegts.js (pas l'etat de session).
    // Utilise par la reconnexion auto : on recree un player sur la meme
    // URL sans casser tsActive/tsMedia (le sender garde sa session).
    function destroyTsPlayer() {
      try { tsVideo.pause(); } catch (e) {}
      if (mpegtsPlayer) {
        try { mpegtsPlayer.unload(); } catch (e) {}
        try { mpegtsPlayer.detachMediaElement(); } catch (e) {}
        try { mpegtsPlayer.destroy(); } catch (e) {}
        mpegtsPlayer = null;
      }
      try { tsVideo.removeAttribute('src'); tsVideo.load(); } catch (e) {}
    }

    function teardownTs() {
      tsActive = false;
      tsBuffering = false;
      tsReconnects = 0;
      tsUrl = null;
      if (tsReconnectTimer) { clearTimeout(tsReconnectTimer); tsReconnectTimer = null; }
      tsVideo.classList.remove('active');
      destroyTsPlayer();
    }

    // Echec definitif du chemin TS : on demonte et on pousse UN status
    // IDLE/ERROR au sender (le telephone affiche alors le bon message
    // "la TV a refuse le flux" au lieu d'un succes fantome).
    function tsFatal(reason) {
      dbg('TS FATAL: ' + reason);
      teardownTs();
      tsErrorPending = true;
      tsBroadcast();
    }

    // Reconnexion auto du flux TS live. Les serveurs IPTV (et certains
    // intermediaires) FERMENT periodiquement la socket HTTP d'un live :
    // sans relance, la TV fige apres 1-2 min alors qu'il suffit de
    // re-tirer la MEME URL. Backoff progressif 1s→5s, max
    // TS_MAX_RECONNECTS tentatives consecutives (compteur remis a zero
    // des que la lecture repart — cf. event 'playing').
    function scheduleTsReconnect(reason) {
      if (!tsActive || !tsUrl) return;
      if (tsReconnects >= TS_MAX_RECONNECTS) {
        tsFatal('flux interrompu apres ' + tsReconnects + ' reconnexions (' + reason + ')');
        return;
      }
      tsReconnects++;
      tsBuffering = true;
      tsBroadcast();
      const delayMs = Math.min(1000 * tsReconnects, 5000);
      dbg('reconnect #' + tsReconnects + ' dans ' + delayMs + 'ms (' + reason + ')');
      if (tsReconnectTimer) clearTimeout(tsReconnectTimer);
      tsReconnectTimer = setTimeout(function () {
        tsReconnectTimer = null;
        if (!tsActive || !tsUrl) return;
        destroyTsPlayer();
        startTsEngine(tsUrl);
      }, delayMs);
    }

    // ---- Events du <video> : verite terrain de la lecture TS --------
    //  Attaches UNE FOIS (l'element est statique). Chaque transition
    //  utile est rebroadcastee aux senders pour que l'UI du telephone
    //  reste alignee (PLAYING/PAUSED/BUFFERING).
    tsVideo.addEventListener('playing', function () {
      if (!tsActive) return;
      tsBuffering = false;
      tsReconnects = 0; // lecture stable → on re-arme le budget reconnexion
      tsBroadcast();
    });
    tsVideo.addEventListener('pause', function () {
      if (!tsActive) return;
      tsBroadcast();
    });
    tsVideo.addEventListener('waiting', function () {
      if (!tsActive) return;
      tsBuffering = true;
      tsBroadcast();
    });
    tsVideo.addEventListener('ended', function () {
      // Un LIVE ne "finit" pas : ended = upstream coupe → on relance.
      if (!tsActive) return;
      scheduleTsReconnect('video ended');
    });
    tsVideo.addEventListener('error', function () {
      if (!tsActive) return;
      const code = tsVideo.error ? tsVideo.error.code : '?';
      scheduleTsReconnect('video error code=' + code);
    });

    // Cree le moteur mpegts.js et demarre la lecture de [url].
    // N'altere PAS l'etat de session (tsActive/tsMedia) — c'est le
    // decoupage qui permet la reconnexion transparente.
    function startTsEngine(url) {
      if (DEBUG) {
        (function () {
          var ctrl = (('AbortController' in window)) ? new AbortController() : null;
          var to = ctrl ? setTimeout(function () { try { ctrl.abort(); } catch (e) {} }, 8000) : null;
          fetch(url, { method: 'GET', signal: ctrl ? ctrl.signal : undefined })
            .then(function (r) {
              var us = r.headers.get('x-upstream-status') || '';
              // 2xx = OK (on coupe le corps sans le lire). Sinon on LIT le
              // corps texte : le proxy y met le vrai status upstream
              // (« upstream status=403 » = fournisseur bloque l'IP proxy,
              //  « upstream status=404 » = token périmé, « unreachable » =
              //  connexion coupée). C'est LA ligne qui dit pourquoi ça échoue.
              if (r.status >= 200 && r.status < 300) {
                dbg('first fetch OK status=' + r.status + ' ct=' + (r.headers.get('content-type') || '?'));
                try { if (r.body && r.body.cancel) r.body.cancel(); } catch (e) {}
                return;
              }
              return r.text().then(function (t) {
                dbg('first fetch status=' + r.status +
                    (us ? ' upstream=' + us : '') +
                    ' body=' + (t || '').slice(0, 100));
              });
            })
            .catch(function (e) { dbg('first fetch FAILED ' + (e && e.name) + ': ' + (e && e.message)); })
            .then(function () { if (to) clearTimeout(to); });
        })();
      }
      mpegtsPlayer = mpegts.createPlayer({
        type: 'mpegts',
        isLive: true,
        url: url,
      }, {
        // Live : pas de buffer infini, on colle au direct.
        liveBufferLatencyChasing: true,
        lazyLoad: false,
        enableWorker: true,
      });
      mpegtsPlayer.attachMediaElement(tsVideo);
      try {
        // Listeners de DEBUG attaches UNE seule fois (startTsEngine est
        // rappele a chaque reconnexion auto — sans le garde-fou, les
        // listeners s'empilaient a chaque relance).
        if (!tsVideo.dataset.dbgWired) {
          tsVideo.dataset.dbgWired = '1';
          var _dbgVideoEvents = ['loadedmetadata', 'playing', 'stalled', 'waiting', 'suspend'];
          _dbgVideoEvents.forEach(function (ev) {
            tsVideo.addEventListener(ev, function () { dbg('video ev=' + ev + ' rt=' + tsVideo.readyState); }, { once: false });
          });
          tsVideo.addEventListener('error', function () {
            var code = tsVideo.error ? tsVideo.error.code : '?';
            dbg('video ERROR code=' + code);
          });
        }
      } catch (e) {}
      mpegtsPlayer.on(mpegts.Events.ERROR, function (type, detail) {
        log('mpegts error', type, detail);
        dbg('mpegts ERROR type=' + type + ' detail=' + detail);
        // NetworkError = socket coupee / HTTP KO → reconnexion auto.
        // MediaError (transmux/codec) → reconnexion aussi : une
        // discontinuite TS mid-stream (pub, changement de profil
        // encodeur) casse le transmux mais repart proprement sur une
        // session fraiche ; le budget TS_MAX_RECONNECTS borne le cas
        // "vraiment indecodable" qui finit en IDLE/ERROR cote sender.
        scheduleTsReconnect('mpegts ' + type);
      });
      mpegtsPlayer.on(mpegts.Events.MEDIA_INFO, function (info) {
        try {
          dbg('MEDIA_INFO video=' + (info && info.videoCodec) +
              ' audio=' + (info && info.audioCodec) +
              ' ' + (info && info.width) + 'x' + (info && info.height));
        } catch (e) { dbg('MEDIA_INFO (unreadable)'); }
      });
      try {
        mpegtsPlayer.on(mpegts.Events.LOADING_COMPLETE, function () {
          dbg('mpegts LOADING_COMPLETE');
          // Sur un LIVE, "loading complete" = l'upstream a FERME le
          // flux (rotation de socket IPTV, proxy coupe…). Ce n'est pas
          // une fin normale → on relance la meme URL.
          scheduleTsReconnect('upstream EOF');
        });
      } catch (e) {}
      mpegtsPlayer.load();
      tsVideo.muted = false;
      const p = tsVideo.play();
      if (p && p.catch) p.catch(function (e) { log('ts autoplay blocked', e); });
    }

    // Demarre une NOUVELLE session de lecture TS (appele par le LOAD
    // interceptor). Retourne false si MSE/mpegts.js indisponibles —
    // le caller laisse alors CAF tenter sa chance.
    function playRawTs(url) {
      teardownTs();
      if (!window.mpegts || !mpegts.isSupported()) {
        log('mpegts.js indisponible — la TV ne supporte pas MSE pour le TS');
        return false;
      }
      tsUrl = url;
      tsActive = true;
      tsBuffering = true; // BUFFERING tant que 'playing' n'a pas confirme
      tsErrorPending = false;
      tsVideo.classList.add('active');
      startTsEngine(url);
      return true;
    }

    // =====================================================
    //  LOAD interceptor — route le flux selon son type
    // =====================================================
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.LOAD,
      function (request) {
        try {
          const media = request.media || {};
          const url = media.contentId || media.contentUrl || '';
          const ct = media.contentType || '';
          try {
            const cd = (request.media && request.media.customData) || request.customData || {};
            if (cd && cd.debug) dbgSetEnabled(true);
          } catch (e) {}
          log('LOAD', url, ct);
          dbg('LOAD contentId=' + url);
          dbg('contentType=' + (ct || '(none)'));

          const useMpegts = isRawMpegTs(url, ct);
          dbg('branch=' + (useMpegts ? 'mpegts.js (raw TS)' : 'CAF native'));
          if (useMpegts) {
            // MPEG-TS brut → mpegts.js sur le <video> dedie. On lance
            // la lecture nous-memes et on renvoie null pour suspendre
            // le pipeline CAF (qui ecran-noirerait sur du TS brut).
            //
            // CONTRAT SENDER (le fix majeur) : renvoyer null NE repond
            // PAS au LOAD — sans reponse, RemoteMediaClient.load() du
            // telephone timeout et l'app declarait "echec" TV allumee.
            // On acquitte donc NOUS-MEMES la commande en poussant un
            // MediaStatus portant le requestId du LOAD (via
            // broadcastStatus + l'interceptor MEDIA_STATUS ci-dessous
            // qui reecrit playerState/media/mediaSessionId).
            const ok = playRawTs(url);
            if (ok) {
              // MediaInformation memorisee telle que recue du sender
              // (titre, image, customData) — completee pour rester
              // coherente : c'est CE media que le MEDIA_STATUS expose.
              media.contentType = ct || 'video/mp2t';
              media.streamType = cast.framework.messages.StreamType.LIVE;
              if (!media.contentId) media.contentId = url;
              tsMedia = media;
              tsBroadcast(request.requestId); // acquitte le LOAD (BUFFERING)
              return null; // suspend le load CAF natif (mpegts.js gere)
            }
            // mpegts.js KO → on laisse CAF tenter sa chance (repli).
          } else {
            // Tout flux NON-TS → pipeline CAF natif. On s'assure que le
            // <video> mpegts est bien rendu et qu'un eventuel flux TS
            // precedent est demonte.
            if (tsActive) teardownTs();
            tsMedia = null; // le status redevient 100% pilote par CAF
          }

          // HLS / DASH / MP4 : normalisations utiles.
          if (/\\.m3u8(\\?|$)/i.test(url) && !media.contentType) {
            media.contentType = 'application/x-mpegURL';
          }
          // Flux live (Xtream / pas de duree) → streamType LIVE, sinon
          // CAF attend une duree et peut rester en buffering.
          if (media.streamType == null &&
              (url.indexOf('/live/') !== -1 || /\\.m3u8(\\?|$)/i.test(url))) {
            media.streamType = cast.framework.messages.StreamType.LIVE;
          }
          request.media = media;
          return request;
        } catch (e) {
          log('LOAD interceptor error', e);
          return request;
        }
      }
    );

    // Quand le sender coupe (STOP) ou met en pause/play, on relaie au
    // lecteur mpegts.js s'il est actif. Chaque commande interceptee
    // (return null) est ACQUITTEE par un MediaStatus portant son
    // requestId — sans ca, le RemoteMediaClient du telephone considere
    // la commande perdue (timeout) meme si la TV a obei.
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.STOP,
      function (request) {
        if (tsActive) {
          teardownTs();
          tsMedia = null;
          tsBroadcast(request.requestId); // status IDLE acquitte le STOP
          return null;
        }
        return request;
      }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PAUSE,
      function (request) {
        if (tsActive) {
          try { tsVideo.pause(); } catch (e) {}
          tsBroadcast(request.requestId);
          return null;
        }
        return request;
      }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PLAY,
      function (request) {
        if (tsActive) {
          try { tsVideo.play(); } catch (e) {}
          tsBroadcast(request.requestId);
          return null;
        }
        return request;
      }
    );

    // =====================================================
    //  MEDIA_STATUS sortant — la TV dit la VERITE au telephone
    // =====================================================
    //  Pendant une lecture mpegts.js, le PlayerManager CAF n'a AUCUN
    //  media charge : son status naturel serait "IDLE sans media", ce
    //  qui faisait croire au sender que rien ne joue. On reecrit donc
    //  chaque MEDIA_STATUS sortant (reponses GET_STATUS periodiques du
    //  SDK sender INCLUSES) avec l'etat reel du <video> TS.
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.MEDIA_STATUS,
      function (status) {
        try {
          if (tsErrorPending) {
            // Echec definitif du TS : UN status IDLE/ERROR puis on rend
            // la main a CAF (le sender mappe idleReason=error sur son
            // message "la TV a refuse le flux").
            tsErrorPending = false;
            status.playerState = cast.framework.messages.PlayerState.IDLE;
            status.idleReason = cast.framework.messages.IdleReason.ERROR;
            if (tsMedia) status.media = tsMedia;
            status.mediaSessionId = TS_MEDIA_SESSION_ID;
            return status;
          }
          if (!tsActive || !tsMedia) return status;
          status.mediaSessionId = TS_MEDIA_SESSION_ID;
          status.media = tsMedia;
          status.playbackRate = 1;
          status.currentTime = tsVideo.currentTime || 0;
          // LIVE IPTV : pause autorisee, pas de seek.
          status.supportedMediaCommands = cast.framework.messages.Command.PAUSE;
          if (tsBuffering) {
            status.playerState = cast.framework.messages.PlayerState.BUFFERING;
          } else if (tsVideo.paused) {
            status.playerState = cast.framework.messages.PlayerState.PAUSED;
          } else {
            status.playerState = cast.framework.messages.PlayerState.PLAYING;
          }
          return status;
        } catch (e) {
          log('MEDIA_STATUS interceptor error', e);
          return status;
        }
      }
    );

    playerManager.addEventListener(
      cast.framework.events.EventType.ERROR,
      function (event) { log('CAF error', event); }
    );

    // =====================================================
    //  Options de demarrage
    // =====================================================
    const options = new cast.framework.CastReceiverOptions();
    // Le receiver reste vivant tant qu'un flux joue (live IPTV =
    // sessions longues, le telephone peut etre eteint).
    options.disableIdleTimeout = true;
    options.statusText = APP;
    context.start(options);
  </script>
</body>
</html>`;
}
