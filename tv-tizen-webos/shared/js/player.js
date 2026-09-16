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
  // Compteur de génération : play() incrémente, stop() invalide. Si le
  // callback prepareAsync d'une ancienne gen se déclenche, on ne lance pas
  // la lecture. AVPlay demande ~150 ms entre close() et le prochain open ;
  // on sérialise via ce compteur plutôt que de close() deux fois.
  var gen = 0;
  var avOpen = false;

  function ensureEls() {
    avplayEl = document.getElementById('av-player');
    videoEl = document.getElementById('html5-video');
  }

  // --- AVPlay (Samsung) ---
  function avPlay(url, myGen) {
    try {
      var listener = {
        onbufferingstart: function () {
          if (myGen !== gen) return;
          DFT.ui && DFT.ui.setBuffering(true);
        },
        onbufferingcomplete: function () {
          if (myGen !== gen) return;
          DFT.ui && DFT.ui.setBuffering(false);
        },
        onstreamcompleted: function () { /* live : ne s'arrête normalement pas */ },
        onerror: function (e) {
          if (myGen !== gen) return;
          DFT.ui && DFT.ui.setPlayerError(String(e && e.name || e));
        },
      };
      // Ne pas close() si rien n'est ouvert (AVPlay n'aime pas le double close).
      if (avOpen) {
        try { webapis.avplay.stop(); } catch (e0) { /* ignore */ }
        try { webapis.avplay.close(); } catch (e1) { /* ignore */ }
        avOpen = false;
      }
      webapis.avplay.open(url);
      avOpen = true;
      webapis.avplay.setDisplayRect(0, 0,
        window.innerWidth || 1920, window.innerHeight || 1080);
      webapis.avplay.setListener(listener);
      webapis.avplay.prepareAsync(function () {
        if (myGen !== gen) return;
        webapis.avplay.play();
      }, function (e) {
        if (myGen !== gen) return;
        DFT.ui && DFT.ui.setPlayerError('prepare: ' + (e && e.name || e));
      });
    } catch (err) {
      DFT.ui && DFT.ui.setPlayerError(String(err));
    }
  }

  function avStop() {
    if (!avOpen) return;
    try { webapis.avplay.stop(); webapis.avplay.close(); } catch (e) { /* ignore */ }
    avOpen = false;
  }

  // --- HTML5 <video> (LG webOS / navigateur) ---
  function htmlPlay(url, myGen) {
    if (!videoEl) return;
    videoEl.style.display = 'block';
    videoEl.onwaiting = function () {
      if (myGen !== gen) return;
      DFT.ui && DFT.ui.setBuffering(true);
    };
    videoEl.onplaying = function () {
      if (myGen !== gen) return;
      DFT.ui && DFT.ui.setBuffering(false);
    };
    videoEl.onerror = function () {
      if (myGen !== gen) return;
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

  function play(url) {
    ensureEls();
    gen++;
    var myGen = gen;
    if (useAvplay) { if (avplayEl) avplayEl.style.display = 'block'; avPlay(url, myGen); }
    else htmlPlay(url, myGen);
  }

  function stop() {
    ensureEls();
    gen++; // invalide tout prepareAsync / callback HTML5 en vol
    if (useAvplay) { avStop(); if (avplayEl) avplayEl.style.display = 'none'; }
    else htmlStop();
  }

  return { play: play, stop: stop };
})();
