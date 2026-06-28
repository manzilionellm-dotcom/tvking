// =========================================================
//  screen_receiver.js — Récepteur « Caster sur un écran »
// =========================================================
//  Page web GÉNÉRIQUE (pas liée à Google Cast) que N'IMPORTE QUEL
//  écran avec un navigateur ouvre : Smart TV (Tizen/webOS/Google TV),
//  un vieux téléviseur avec navigateur, un PC, un vidéoprojecteur
//  connecté… L'utilisateur ouvre `app.7themotion.com/e/<CODE>` (ou
//  scanne le QR depuis le téléphone).
//
//  Cross-réseau : TOUT passe par le Worker (HTTPS). La TV ne parle
//  jamais au téléphone → pas besoin d'être sur le même Wi-Fi, pas de
//  souci d'« AP isolation ». Le flux IPTV est proxifié par la route
//  /cs/<b64>.ts du Worker (déjà en place) et lu ici par mpegts.js
//  (transmux MPEG-TS → fMP4 via Media Source Extensions).
//
//  Signalisation par POLLING léger (pas de WebSocket → pas besoin de
//  Durable Objects) : la page demande `GET /api/screen/<CODE>` toutes
//  les ~1,5 s et réagit aux changements de `seq`.
//
//  Limite connue : un navigateur de TV ne décode pas le HEVC/H265
//  (et on ne peut pas transcoder sur un Worker). Sur échec de lecture,
//  on affiche un repli clair (« utilise Chromecast / DLNA »).
// =========================================================

// Page d'APPAIRAGE servie à /ecran : la TV (qui n'a PAS de caméra et ne
// scanne donc rien) ouvre cette adresse FIXE une fois, puis l'utilisateur
// tape le code à 4 caractères affiché sur son téléphone → redirige vers
// /e/<CODE>. C'est le modèle « entrer le code sur la TV » de YouTube /
// Netflix : seul le code change, l'adresse reste mémorisable.
export function screenPairHtml() {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION — Écran</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:#0A0A0C;color:#fff;
    font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
  .wrap{position:fixed;inset:0;display:flex;flex-direction:column;
    align-items:center;justify-content:center;text-align:center;padding:6vh 5vw}
  .logo{font-size:clamp(28px,6vw,64px);font-weight:800;letter-spacing:.06em;margin-bottom:2vh}
  .logo b{color:#D63A30}
  .hint{font-size:clamp(15px,2.4vw,26px);color:#9aa;max-width:760px;line-height:1.5;margin-bottom:5vh}
  form{display:flex;flex-direction:column;align-items:center;gap:3.2vh}
  input{font-size:clamp(40px,10vw,110px);font-weight:800;letter-spacing:.22em;
    text-align:center;text-transform:uppercase;width:min(90vw,8em);
    background:#121216;color:#fff;border:3px solid #2a2a30;border-radius:18px;
    padding:.18em .1em;caret-color:#D63A30}
  input:focus{outline:none;border-color:#D63A30}
  button{font-size:clamp(18px,2.6vw,30px);font-weight:700;color:#fff;
    background:#D63A30;border:none;border-radius:14px;padding:.7em 2.4em;cursor:pointer}
  button:focus{outline:3px solid #fff;outline-offset:3px}
  .err{color:#D63A30;font-size:clamp(14px,2vw,20px);min-height:1.4em;margin-top:1vh}
</style>
</head>
<body>
  <div class="wrap">
    <div class="logo">7&nbsp;<b>MOTION</b></div>
    <div class="hint">Entre le code à 4&nbsp;caractères affiché sur ton téléphone
      (rubrique « Caster sur un écran »).</div>
    <form id="f">
      <input id="c" autocomplete="off" autocapitalize="characters"
        autocorrect="off" spellcheck="false" maxlength="4"
        inputmode="text" placeholder="––––" autofocus>
      <button type="submit">Valider</button>
      <div class="err" id="e"></div>
    </form>
  </div>
<script>
(function(){
  var input=document.getElementById('c'), err=document.getElementById('e');
  document.getElementById('f').addEventListener('submit',function(ev){
    ev.preventDefault();
    var code=(input.value||'').toUpperCase().replace(/[^2-9A-Z]/g,'');
    if(code.length!==4){ err.textContent='Code à 4 caractères (chiffres 2-9 et lettres).'; return; }
    window.location.href='/e/'+code;
  });
  input.addEventListener('input',function(){
    input.value=(input.value||'').toUpperCase().replace(/[^2-9A-Z]/g,'').slice(0,4);
    err.textContent='';
  });
})();
</script>
</body>
</html>`;
}

export function screenReceiverHtml(code) {
  const safeCode = String(code || '').replace(/[^0-9A-Za-z]/g, '').slice(0, 8);
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>7 MOTION — Écran</title>
<script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"></script>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { width:100%; height:100%; background:#0A0A0C; color:#fff;
    font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
    overflow:hidden; }
  #video { position:fixed; inset:0; width:100%; height:100%;
    background:#000; object-fit:contain; display:none; }
  #video.active { display:block; }
  #panel { position:fixed; inset:0; display:flex; flex-direction:column;
    align-items:center; justify-content:center; text-align:center; padding:6vh 4vw; }
  #panel.hidden { display:none; }
  .logo { font-size:clamp(28px,6vw,64px); font-weight:800; letter-spacing:.06em;
    color:#fff; margin-bottom:3vh; }
  .logo b { color:#D63A30; }
  .hint { font-size:clamp(15px,2.2vw,24px); color:#9aa; max-width:680px;
    line-height:1.5; }
  .codebox { margin-top:4vh; padding:2.4vh 5vw; border:2px solid #2a2a30;
    border-radius:18px; background:#121216; }
  .codelbl { font-size:clamp(12px,1.6vw,16px); color:#778; text-transform:uppercase;
    letter-spacing:.18em; margin-bottom:1.2vh; }
  .code { font-size:clamp(40px,9vw,96px); font-weight:800; letter-spacing:.14em;
    color:#D63A30; font-variant-numeric:tabular-nums; }
  .dot { display:inline-block; width:.5em; height:.5em; border-radius:50%;
    background:#3a3; margin-right:.5em; vertical-align:middle;
    animation:pulse 1.6s ease-in-out infinite; }
  @keyframes pulse { 0%,100%{opacity:.35} 50%{opacity:1} }
  #err { position:fixed; left:0; right:0; bottom:0; padding:2.4vh 4vw;
    background:rgba(214,58,48,.92); color:#fff; font-size:clamp(15px,2.2vw,22px);
    text-align:center; display:none; }
  #err.show { display:block; }
</style>
</head>
<body>
  <video id="video" playsinline webkit-playsinline autoplay></video>

  <div id="panel">
    <div class="logo">7&nbsp;<b>MOTION</b></div>
    <div class="hint">Prêt à recevoir ta vidéo. Depuis ton téléphone&nbsp;7&nbsp;MOTION,
      appuie sur « Caster sur un écran » et scanne le QR — ou vérifie que le code
      ci-dessous correspond.</div>
    <div class="codebox">
      <div class="codelbl"><span class="dot"></span>Connecté · code de l'écran</div>
      <div class="code" id="code">${safeCode}</div>
    </div>
  </div>

  <div id="err"></div>

<script>
(function(){
  var CODE = ${JSON.stringify(safeCode)};
  var POLL_MS = 1500;
  var video = document.getElementById('video');
  var panel = document.getElementById('panel');
  var errEl = document.getElementById('err');
  var player = null;        // instance mpegts.js courante
  var lastSeq = -1;         // dernière commande appliquée
  var curUrl = null;        // URL en cours de lecture

  function showPanel(on){ panel.classList.toggle('hidden', !on); }
  function showErr(msg){ if(!msg){ errEl.classList.remove('show'); return; }
    errEl.textContent = msg; errEl.classList.add('show'); }

  function teardown(){
    try { if (player){ player.destroy(); player = null; } } catch(e){}
    try { video.removeAttribute('src'); video.load(); } catch(e){}
    video.classList.remove('active');
    curUrl = null;
  }

  var triedNative = false;

  function activate(){
    showPanel(false);
    video.classList.add('active');
    video.muted = false;
    var p = video.play();
    if (p && p.catch) p.catch(function(){
      // Autoplay bloqué : on tente en muet (la TV débloque au 1er geste).
      video.muted = true; video.play().catch(function(){});
    });
  }

  // Stratégie 2 : décodeur NATIF de la TV. Beaucoup de Smart TV ont le
  // HEVC/H265 en MATÉRIEL (contrairement à Chrome desktop) → ce repli les
  // récupère GRATUITEMENT, sans serveur de transcodage.
  function tryNative(url){
    triedNative = true;
    try { if (player){ player.destroy(); player = null; } } catch(e){}
    try {
      video.src = url;
      video.onerror = function(){
        showErr("Codec non lisible sur cet écran (souvent HEVC/H265). "
          + "Utilise Chromecast ou DLNA pour cette chaîne.  [MediaError natif]");
      };
      activate();
      curUrl = url;
    } catch(e){
      showErr("Lecture impossible sur cet écran. Utilise Chromecast ou DLNA.");
    }
  }

  function playStream(url){
    teardown();
    showErr('');
    triedNative = false;
    // Stratégie 1 : mpegts.js (transmux TS H.264 → marche partout, même
    // Chrome). Sur erreur codec, on bascule sur le décodeur natif (st. 2).
    if (window.mpegts && mpegts.isSupported()){
      try {
        player = mpegts.createPlayer(
          { type:'mpegts', isLive:true, url:url },
          { liveBufferLatencyChasing:true, lazyLoad:false, enableWorker:true }
        );
        player.attachMediaElement(video);
        player.on(mpegts.Events.ERROR, function(type, detail){
          if (type === 'NetworkError'){
            // On récupère le VRAI code HTTP du serveur IPTV (exposé par le
            // proxy) pour diagnostiquer : 403 = IP bloquée, 5xx/limite =
            // trop de connexions, 404 = URL.
            fetch(url).then(function(r){
              var us = r.headers.get('X-Upstream-Status') || String(r.status);
              try { if (r.body) r.body.cancel(); } catch(e){}
              showErr("Le serveur IPTV refuse la connexion du relais — code " + us
                + ". Souvent : limite de connexions atteinte (ton téléphone joue "
                + "déjà la chaîne) OU l'IP du serveur bloque le cloud.  [HTTP " + us + "]");
            }).catch(function(){
              showErr("Serveur IPTV / réseau injoignable depuis le relais.  [NetworkError]");
            });
          } else if (!triedNative){
            // MediaError / autre (souvent HEVC) → décodeur natif de la TV.
            tryNative(url);
          }
        });
        player.load();
        activate();
        curUrl = url;
        return;
      } catch(e){ /* on tombe sur le natif ci-dessous */ }
    }
    tryNative(url);
  }

  function apply(state){
    if (!state) return;
    var a = state.action;
    if (a === 'expired'){ teardown(); showPanel(true); showErr("Session expirée — relance le cast depuis le téléphone."); return; }
    var seq = state.seq || 0;

    if (a === 'play'){
      if (seq !== lastSeq || state.playUrl !== curUrl){
        lastSeq = seq;
        if (state.playUrl) playStream(state.playUrl);
      }
      return;
    }
    if (a === 'control'){
      lastSeq = seq;
      try { if (state.paused) video.pause(); else video.play().catch(function(){}); } catch(e){}
      return;
    }
    if (a === 'idle' || a === 'stop'){
      if (seq !== lastSeq){ lastSeq = seq; teardown(); showPanel(true); showErr(''); }
      return;
    }
  }

  var failures = 0;
  function poll(){
    fetch('/api/screen/' + CODE, { cache:'no-store' })
      .then(function(r){ return r.json(); })
      .then(function(s){ failures = 0; apply(s); })
      .catch(function(){ failures++; if (failures === 5) showErr("Connexion au serveur perdue — on réessaie…"); })
      .then(function(){ setTimeout(poll, POLL_MS); });
  }
  poll();

  // Garde l'écran réveillé tant que possible (best-effort).
  try {
    if (navigator.wakeLock && navigator.wakeLock.request){
      var reacquire = function(){ navigator.wakeLock.request('screen').catch(function(){}); };
      reacquire();
      document.addEventListener('visibilitychange', function(){
        if (document.visibilityState === 'visible') reacquire();
      });
    }
  } catch(e){}
})();
</script>
</body>
</html>`;
}
