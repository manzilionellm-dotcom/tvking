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
  // Par defaut on prend le branding 7 MOTION ; ?app=redroom bascule
  // sur le velours / le R rouge.
  const isRedRoom = flavor === 'redroom';
  const appName = isRedRoom ? 'Red Room' : '7 MOTION';
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
  <script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"></script>
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
  </style>
</head>
<body>
  <!-- Pipeline CAF natif : splash + lecture HLS/DASH/MP4. -->
  <cast-media-player></cast-media-player>

  <!-- Element dedie au MPEG-TS brut (mpegts.js). Affiche par-dessus
       le cast-media-player seulement pendant une lecture TS. -->
  <video id="ts-video" playsinline></video>

  <div class="brand-watermark">${appName}</div>

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

    // ---- Helpers -------------------------------------------------
    function log() {
      try { console.log.apply(console, ['[' + APP + ' cast]'].concat([].slice.call(arguments))); } catch (e) {}
    }

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

    function teardownTs() {
      tsActive = false;
      tsVideo.classList.remove('active');
      try { tsVideo.pause(); } catch (e) {}
      if (mpegtsPlayer) {
        try { mpegtsPlayer.unload(); } catch (e) {}
        try { mpegtsPlayer.detachMediaElement(); } catch (e) {}
        try { mpegtsPlayer.destroy(); } catch (e) {}
        mpegtsPlayer = null;
      }
      try { tsVideo.removeAttribute('src'); tsVideo.load(); } catch (e) {}
    }

    // Lance un flux MPEG-TS brut via mpegts.js sur le <video> dedie.
    function playRawTs(url) {
      teardownTs();
      if (!window.mpegts || !mpegts.isSupported()) {
        log('mpegts.js indisponible — la TV ne supporte pas MSE pour le TS');
        return false;
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
      mpegtsPlayer.on(mpegts.Events.ERROR, function (type, detail) {
        log('mpegts error', type, detail);
      });
      mpegtsPlayer.load();
      tsVideo.muted = false;
      const p = tsVideo.play();
      if (p && p.catch) p.catch(function (e) { log('ts autoplay blocked', e); });
      tsActive = true;
      tsVideo.classList.add('active');
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
          log('LOAD', url, ct);

          if (isRawMpegTs(url, ct)) {
            // MPEG-TS brut → mpegts.js sur le <video> dedie. On indique
            // a CAF que le contenu est gere en externe : on lance la
            // lecture nous-memes et on renvoie null pour suspendre le
            // pipeline CAF (qui ecran-noirerait sur du TS brut).
            const ok = playRawTs(url);
            if (ok) {
              // Met a jour le MediaInformation pour que le sender voie
              // un etat coherent (titre, live).
              return null; // suspend le load CAF natif (mpegts.js gere)
            }
            // mpegts.js KO → on laisse CAF tenter sa chance (repli).
          } else {
            // Tout flux NON-TS → pipeline CAF natif. On s'assure que le
            // <video> mpegts est bien rendu et qu'un eventuel flux TS
            // precedent est demonte.
            if (tsActive) teardownTs();
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
    // lecteur mpegts.js s'il est actif.
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.STOP,
      function (request) { if (tsActive) teardownTs(); return request; }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PAUSE,
      function (request) { if (tsActive) { try { tsVideo.pause(); } catch (e) {} return null; } return request; }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PLAY,
      function (request) { if (tsActive) { try { tsVideo.play(); } catch (e) {} return null; } return request; }
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
