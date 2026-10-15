// =========================================================
//  platform.js — Détection de la plateforme TV + touches télécommande
// =========================================================
//  On distingue Tizen (Samsung), webOS (LG) et 'browser' (dev sur PC). Chaque
//  plateforme a SES codes de touches « Retour » → on les unifie ici.
// =========================================================
window.DFT = window.DFT || {};

DFT.platform = (function () {
  if (typeof window.tizen !== 'undefined') return 'tizen';
  var ua = navigator.userAgent || '';
  if (typeof window.webOS !== 'undefined' ||
      ua.indexOf('Web0S') > -1 || ua.indexOf('webOS') > -1) {
    return 'webos';
  }
  return 'browser';
})();

// Codes de touches D-pad unifiés. Les flèches + OK (13) sont communs ; seule
// la touche RETOUR diffère (Tizen 10009, webOS 461, navigateur Backspace 8).
DFT.keys = {
  LEFT: 37,
  UP: 38,
  RIGHT: 39,
  DOWN: 40,
  ENTER: 13,
  // Liste car certaines plateformes émettent plusieurs codes pour « Retour ».
  BACK: [10009, 461, 8, 27],
};

DFT.isBack = function (keyCode) {
  return DFT.keys.BACK.indexOf(keyCode) > -1;
};

// Les flèches, OK et Retour sont reçus sans inscription. Les touches média
// nécessitent tv.inputdevice ; une touche absente ne doit pas bloquer les autres.
DFT.registerKeys = function () {
  if (DFT.platform !== 'tizen' || !window.tizen || !tizen.tvinputdevice) return;
  ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop'].forEach(function (key) {
    try { tizen.tvinputdevice.registerKey(key); } catch (e) { /* modèle sans cette touche */ }
  });
};
