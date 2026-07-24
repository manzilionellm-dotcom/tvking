// =========================================================
//  mediaKeys.js — Contrat des touches MÉDIA de la télécommande
// =========================================================
//  platform.js DÉCLARE déjà les touches média sur Tizen
//  (tizen.tvinputdevice.registerKey 'MediaPlayPause' / 'MediaPlay' /
//  'MediaPause' / 'MediaStop') — mais AUCUN code ne les consommait : elles
//  arrivaient et étaient ignorées. Ce module rend le contrat explicite et
//  testable ; nav.js le branche sur des actions réelles dans l'écran lecteur.
//
//  Live TV : pas d'épisode « suivant » ni de seek → on mappe seulement
//  toggle (play/pause) et stop (fermer le lecteur). On n'invente rien.
//
//  Pur (aucun DOM), ES5, exposé en global (DFT.mediaKeys) et en CommonJS.
// =========================================================
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; }
  root.DFT = root.DFT || {};
  root.DFT.mediaKeys = api;
})(typeof window !== 'undefined' ? window : this, function () {
  'use strict';

  // Nom de touche média (KeyboardEvent.key, ou nom normalisé côté Tizen)
  // → action, ou null si non mappée.
  function mediaKeyAction(key) {
    switch (key) {
      case 'MediaPlayPause':
      case 'MediaPlay':
      case 'MediaPause':
        return 'toggle';
      case 'MediaStop':
        return 'stop';
      default:
        return null;
    }
  }

  return { mediaKeyAction: mediaKeyAction };
});
