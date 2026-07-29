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
  var avplayEl = null;
  var videoEl = null;

  function ensureEls() {
    avplayEl = document.getElementById('av-player');
    videoEl = document.getElementById('html5-video');
  }

  // --- AVPlay (Samsung) ---
  function avPlay(url) {
    try {
      var listener = {
        onbufferingstart: function () { DFT.ui && DFT.ui.setBuffering(true); },
        onbufferingcomplete: function () { DFT.ui && DFT.ui.setBuffering(false); },
        onstreamcompleted: function () { /* live : ne s'arrête normalement pas */ },
        onerror: function (e) { DFT.ui && DFT.ui.setPlayerError(String(e && e.name || e)); },
      };
      webapis.avplay.close();
      webapis.avplay.open(url);
      webapis.avplay.setDisplayRect(0, 0,
        window.innerWidth || 1920, window.innerHeight || 1080);
      webapis.avplay.setListener(listener);
      webapis.avplay.prepareAsync(function () {
        webapis.avplay.play();
      }, function (e) {
        DFT.ui && DFT.ui.setPlayerError('prepare: ' + (e && e.name || e));
      });
    } catch (err) {
      DFT.ui && DFT.ui.setPlayerError(String(err));
    }
  }

  function avStop() {
    try { webapis.avplay.stop(); webapis.avplay.close(); } catch (e) { /* ignore */ }
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
    if (p && p.catch) p.catch(function () { /* autoplay : ignoré sur TV */ });
  }

  function htmlStop() {
    if (!videoEl) return;
    try { videoEl.pause(); videoEl.removeAttribute('src'); videoEl.load(); } catch (e) {}
    videoEl.style.display = 'none';
  }

  var paused = false;

  function play(url) {
    ensureEls();
    paused = false;
    if (useAvplay) { if (avplayEl) avplayEl.style.display = 'block'; avPlay(url); }
    else htmlPlay(url);
  }

  function stop() {
    ensureEls();
    paused = false;
    if (useAvplay) { avStop(); if (avplayEl) avplayEl.style.display = 'none'; }
    else htmlStop();
  }

  // Pause / reprise (touche média de la télécommande). Best-effort et
  // TOUJOURS enveloppé : une touche média ne doit jamais planter l'app ni
  // toucher les chemins play()/stop() existants.
  function setPaused(on) {
    try {
      if (useAvplay) {
        if (on) { webapis.avplay.pause(); } else { webapis.avplay.play(); }
      } else if (videoEl) {
        if (on) { videoEl.pause(); }
        else { var p = videoEl.play(); if (p && p.catch) p.catch(function () {}); }
      }
      paused = on;
    } catch (e) { /* best-effort */ }
  }

  function toggle() { setPaused(!paused); }

  return {
    play: play, stop: stop,
    toggle: toggle, setPaused: setPaused,
    isPaused: function () { return paused; },
  };
})();
