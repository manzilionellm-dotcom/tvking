// =========================================================
//  cast_receiver.js — HTML du Cast Receiver custom 7 MOTION / Red Room
// =========================================================
//  Exposee par worker.js sur la route GET /cast-receiver.
//  URL publique a coller dans la Google Cast SDK Developer
//  Console pour obtenir un Receiver Application ID.
//
//  ARCHITECTURE :
//    - Page HTML autonome, hebergee par notre Worker
//    - Charge le CAF (Cast Application Framework) Receiver SDK v3
//      depuis le CDN officiel Google
//    - Utilise <cast-media-player> qui fournit GRATUITEMENT :
//        - Lecture HLS / DASH / MPEG-TS / MP4 (autoplay quand le
//          sender envoie une LoadRequest)
//        - Bare controls : play/pause, seek, volume, qualite
//        - Sous-titres si presents
//        - Idle screen avec notre logo quand rien ne joue
//    - On customize via les CSS variables documentees par Google :
//        --background-color, --logo-image, --splash-image,
//        --progress-color, etc.
//
//  BRANDING :
//    Comme on a 2 apps (7 MOTION + Red Room), on differencie via
//    un query param ?app=redroom dans l'URL receiver. La Console
//    Google accepte une URL avec query strings.
//    → 7 MOTION inscrira `https://99999.7themotion.com/cast-receiver`
//    → Red Room inscrira `https://99999.7themotion.com/cast-receiver?app=redroom`
//    Chacun aura son propre Application ID, et le sender Android
//    enverra a l'ID correspondant a son flavor.
//
//  REFERENCE :
//    https://developers.google.com/cast/docs/web_receiver/styled_media_receiver
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
    CAF Receiver SDK v3 (Cast Application Framework).
    C'est ce qui transforme cette page en receiver Cast officiel.
    Sans ce script, le Chromecast ne sait pas quoi faire.
  -->
  <script src="//www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js"></script>
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

    /* ===== <cast-media-player> : le composant officiel CAF =====
       Toutes ces variables sont documentees par Google et stylent
       l'idle screen + les controles overlay pendant la lecture.   */
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

    /* ===== Watermark coin bas-droite pendant la lecture =====
       Discret, comme un logo de chaine TV. Apparait par dessus la
       video sans la masquer.                                       */
    .brand-watermark {
      position: fixed;
      right: 24px;
      bottom: 24px;
      z-index: 2;
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
  <!-- Le composant principal CAF qui gere la lecture video et
       affiche le splash screen avec notre logo quand rien ne joue. -->
  <cast-media-player></cast-media-player>

  <!-- Watermark de marque, visible en transparence sur la video. -->
  <div class="brand-watermark">${appName}</div>

  <script>
    // ===== Boot du receiver =====
    // Recupere l'instance CastReceiverContext (singleton fourni
    // par le CAF SDK) et la demarre. Sans .start() le Chromecast
    // affiche un ecran d'erreur generique apres ~10s.
    const context = cast.framework.CastReceiverContext.getInstance();
    const playerManager = context.getPlayerManager();

    // ===== Diagnostic console (utile pour debug remote) =====
    // L'app Cast Connect debug du Chrome permet d'inspecter cette
    // console depuis l'ordi. Aide a savoir ce que le sender envoie.
    playerManager.addEventListener(
      cast.framework.events.EventType.MEDIA_INFORMATION_CHANGED,
      function(event) {
        console.log('[${appName} cast] media info :', event.mediaInformation);
      }
    );

    playerManager.addEventListener(
      cast.framework.events.EventType.ERROR,
      function(event) {
        console.error('[${appName} cast] error :', event);
      }
    );

    // ===== Options de demarrage =====
    // STATUS_TEXT visible en haut de l'idle screen avec le logo.
    const options = new cast.framework.CastReceiverOptions();
    options.disableIdleTimeout = false;   // ferme apres 5 min d'inactivite (defaut)
    options.statusText = '${appName}';
    context.start(options);
  </script>
</body>
</html>`;
}
