// =========================================================
//  player.js — Lecture vidéo NATIVE par plateforme
// =========================================================
//  IMPORTANT : sur Tizen/webOS le lecteur Android (ExoPlayer/Media3) n'existe
//  pas. On utilise la vidéo NATIVE de chaque TV :
//    • Samsung Tizen → AVPlay (webapis.avplay) sur un <object avplayer>.
//    • LG webOS / navigateur → élément HTML5 <video> (HLS/TS natif TV).
//  API unifiée : DFT.player.play(url) / DFT.player.stop().
// =========================================================
window.DFT = window.DFT || {};

DFT.player = (function () {
  var useAvplay = (DFT.platform === 'tizen');
  var generation = 0;
  var avplayEl = null;
  var videoEl = null;

  function ensureEls() {
    avplayEl = document.getElementById('av-player');
    videoEl = document.getElementById('html5-video');
  }

  // --- AVPlay (Samsung) ---
  function avPlay(url) {
    var token = ++generation;
    try {
      if (!window.webapis || !webapis.avplay) throw new Error("API Samsung AVPlay indisponible");
      var listener = {
        onbufferingstart: function () { DFT.ui && DFT.ui.setBuffering(true); },
        onbufferingcomplete: function () { DFT.ui && DFT.ui.setBuffering(false); },
        onstreamcompleted: function () { /* live : ne s'arrête normalement pas */ },
        onerror: function (e) { DFT.ui && DFT.ui.setPlayerError(String(e && e.name || e)); },
      };
      if (webapis.avplay.getState() !== 'NONE') webapis.avplay.close();
      webapis.avplay.open(url);
      webapis.avplay.setDisplayRect(0, 0,
        window.innerWidth || 1920, window.innerHeight || 1080);
      webapis.avplay.setListener(listener);
      webapis.avplay.prepareAsync(function () {
        if (token !== generation) return;
        try { webapis.avplay.play(); } catch (e) { DFT.ui.setPlayerError(e.name); }
      }, function (e) {
        if (token !== generation) return;
        DFT.ui && DFT.ui.setPlayerError('prepare: ' + (e && e.name || e));
      });
    } catch (err) {
      DFT.ui && DFT.ui.setPlayerError(String(err));
    }
  }

  function avStop() {
    generation++;
    try { webapis.avplay.stop(); } catch (e) { /* déjà arrêté */ }
    try { webapis.avplay.close(); } catch (e) { /* API absente ou lecteur fermé */ }
  }

  // --- HTML5 <video> (LG webOS / navigateur) ---
  function htmlPlay(url) {
    if (!videoEl) return;
    videoEl.style.display = 'block';
    videoEl.onwaiting = function () { DFT.ui && DFT.ui.setBuffering(true); };
    videoEl.onplaying = function () { DFT.ui && DFT.ui.setBuffering(false); };
    videoEl.onerror = function () {
      DFT.ui && DFT.ui.setPlayerError('Lecture impossible (format non supporté ?)');
    };
    videoEl.src = url;
    var p = videoEl.play();
    if (p && p.catch) p.catch(function () { DFT.ui.setPlayerError('Démarrage vidéo impossible. Réessayez.'); });
  }

  function htmlStop() {
    if (!videoEl) return;
    try { videoEl.pause(); videoEl.removeAttribute('src'); videoEl.load(); } catch (e) {}
    videoEl.style.display = 'none';
  }

  function play(url) {
    ensureEls();
    if (useAvplay) { if (avplayEl) avplayEl.style.display = 'block'; avPlay(url); }
    else htmlPlay(url);
  }

  function stop() {
    ensureEls();
    if (useAvplay) { avStop(); if (avplayEl) avplayEl.style.display = 'none'; }
    else htmlStop();
  }

  // Les touches média sont traitées seulement lorsqu’un lecteur est visible.
  function media(key) {
    ensureEls();
    try {
      if (useAvplay && window.webapis && webapis.avplay) {
        var state = webapis.avplay.getState();
        if (key === 413) { stop(); return; }
        if (key === 19 || (key === 10252 && state === 'PLAYING')) webapis.avplay.pause();
        else if (key === 415 || key === 10252) webapis.avplay.play();
      } else if (videoEl && videoEl.src) {
        if (key === 413) stop();
        else if (key === 19 || (key === 10252 && !videoEl.paused)) videoEl.pause();
        else { var result = videoEl.play(); if (result && result.catch) result.catch(function () { DFT.ui.setPlayerError('Reprise impossible'); }); }
      }
    } catch (e) { DFT.ui.setPlayerError('Commande vidéo indisponible'); }
  }
  return { play: play, stop: stop, media: media };
})();
