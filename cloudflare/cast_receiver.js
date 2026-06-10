// =========================================================
//  cast_receiver.js — Cast Receiver custom 7 MOTION (mpegts.js)
// =========================================================
//  Exposé par worker.js sur la route GET /cast-receiver.
//  URL à coller dans la Google Cast SDK Developer Console pour obtenir
//  un Receiver Application ID (le nôtre : 46F815A5).
//
//  POURQUOI CE RECEIVER CUSTOM (et pas le Default Media Receiver) :
//    Google Cast (Chromecast / Google TV / SHIELD) ne décode PAS le
//    MPEG-TS brut (`.ts` / `video/mp2t`) — le format IPTV le plus
//    courant. Le receiver par défaut affiche alors l'écran « cast »
//    SANS image (constaté sur SHIELD). On ajoute donc :
//      - mpegts.js : décode le MPEG-TS LIVE via Media Source Extensions
//        directement dans le receiver → la TV Google joue enfin le flux.
//      - hls.js    : pour les flux HLS (.m3u8) si jamais.
//      - lecture native <video> pour le MP4.
//
//  TECHNIQUE ANTI-CLOBBER : on intercepte le LOAD du CAF. Pour le TS/HLS,
//  on attache mpegts.js/hls.js à NOTRE <video> (ce qui pose un src=blob:
//  MSE), PUIS on récrit `contentUrl` du LOAD avec ce blob et le type
//  video/mp4 → le CAF « charge » le même blob (pas d'écrasement) et
//  rapporte correctement l'état PLAYING au téléphone.
//
//  LG / Samsung passent par le DLNA (autre chemin, non concerné ici).
// =========================================================

export function castReceiverHtml(flavor) {
  const isRedRoom = flavor === 'redroom';
  const appName = isRedRoom ? 'Red Room' : '7 MOTION';
  const accent = '#D63A30';
  const bg = isRedRoom ? '#08060A' : '#0A0A0C';
  const logoUrl =
    'https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg';

  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${appName} · Cast</title>
  <!-- CAF Receiver SDK v3 -->
  <script src="//www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js"></script>
  <!-- mpegts.js : lecture MPEG-TS live via MSE (le cœur du fix). -->
  <script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"></script>
  <!-- hls.js : lecture HLS (.m3u8) si le flux en est. -->
  <script src="//cdn.jsdelivr.net/npm/hls.js@1.5.15/dist/hls.min.js"></script>
  <style>
    html, body {
      margin: 0; padding: 0; background: ${bg}; color: #F2F2F4;
      width: 100%; height: 100%; overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    #v { position: fixed; inset: 0; width: 100%; height: 100%;
         background: ${bg}; object-fit: contain; z-index: 1; }
    /* Splash logo affiché tant que rien ne joue. */
    #splash {
      position: fixed; inset: 0; z-index: 3; display: flex;
      align-items: center; justify-content: center; flex-direction: column;
      background: ${bg}; transition: opacity .35s ease;
    }
    #splash.hidden { opacity: 0; pointer-events: none; }
    #splash img { width: 160px; height: 160px; border-radius: 28px;
                  object-fit: cover; box-shadow: 0 0 60px rgba(214,58,48,.45); }
    #splash .name { margin-top: 18px; font-size: 22px; font-weight: 800;
                    letter-spacing: 1px; }
    #splash .sub { margin-top: 6px; font-size: 12px; letter-spacing: 3px;
                   color: rgba(255,255,255,.55); text-transform: uppercase; }
    .brand-watermark {
      position: fixed; right: 24px; bottom: 24px; z-index: 2; opacity: .55;
      pointer-events: none; font-size: 11px; letter-spacing: 3px;
      font-weight: 700; color: rgba(255,255,255,.85);
      text-shadow: 0 2px 8px rgba(0,0,0,.8);
    }
    .brand-watermark::before {
      content: ''; display: inline-block; width: 6px; height: 6px;
      border-radius: 50%; background: ${accent}; margin-right: 8px;
      vertical-align: middle;
    }
  </style>
</head>
<body>
  <video id="v" autoplay playsinline></video>
  <div id="splash">
    <img src="${logoUrl}" alt="${appName}">
    <div class="name">${appName}</div>
    <div class="sub">Prêt à diffuser</div>
  </div>
  <div class="brand-watermark">${appName}</div>

  <script>
    (function () {
      var video = document.getElementById('v');
      var splash = document.getElementById('splash');
      var tsPlayer = null;
      var hls = null;

      function showSplash(s) {
        if (s) splash.classList.remove('hidden');
        else splash.classList.add('hidden');
      }
      // Dès que la vidéo joue vraiment, on cache le splash.
      video.addEventListener('playing', function () { showSplash(false); });
      video.addEventListener('emptied', function () { showSplash(true); });
      video.addEventListener('ended', function () { showSplash(true); });

      function teardown() {
        if (tsPlayer) { try { tsPlayer.destroy(); } catch (e) {} tsPlayer = null; }
        if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
      }

      var context = cast.framework.CastReceiverContext.getInstance();
      var playerManager = context.getPlayerManager();

      // ===== Interception du LOAD : c'est ICI qu'on décode le MPEG-TS. =====
      playerManager.setMessageInterceptor(
        cast.framework.messages.MessageType.LOAD,
        function (request) {
          try {
            var media = request.media || {};
            var url = media.contentUrl || media.contentId || '';
            var ct = (media.contentType || '').toLowerCase();
            var isHls = ct.indexOf('mpegurl') >= 0 || /\\.m3u8(\\?|$)/i.test(url);
            var isTs = !isHls && (
              ct.indexOf('mp2t') >= 0 || ct.indexOf('mpegts') >= 0 ||
              /\\.ts(\\?|$)/i.test(url) || /\\/live\\//i.test(url)
            );
            teardown();

            if (isTs && window.mpegts && mpegts.isSupported()) {
              tsPlayer = mpegts.createPlayer(
                { type: 'mpegts', isLive: true, url: url },
                { liveBufferLatencyChasing: true, lazyLoad: false }
              );
              tsPlayer.attachMediaElement(video);
              tsPlayer.load();
              // Anti-clobber : le CAF chargera le MÊME blob MSE.
              request.media.contentUrl = video.src;
              request.media.contentType = 'video/mp4';
            } else if (isHls && window.Hls && Hls.isSupported()) {
              hls = new Hls({ lowLatencyMode: true });
              hls.loadSource(url);
              hls.attachMedia(video);
              request.media.contentUrl = video.src;
              request.media.contentType = 'video/mp4';
            }
            // MP4 / autres : on laisse le CAF gérer nativement.
          } catch (e) {
            // En cas de pépin, on laisse le LOAD passer tel quel au CAF.
          }
          return request;
        }
      );

      playerManager.addEventListener(
        cast.framework.events.EventType.ERROR,
        function (event) { console.error('[${appName} cast] error', event); }
      );

      var options = new cast.framework.CastReceiverOptions();
      options.disableIdleTimeout = false;
      options.statusText = '${appName}';
      context.start(options);
    })();
  </script>
</body>
</html>`;
}
