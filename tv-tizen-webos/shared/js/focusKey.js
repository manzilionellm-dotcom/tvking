// =========================================================
//  focusKey.js — Clé de focus stable + mémoire de focus par écran
// =========================================================
//  Sur une TV, perdre sa place coûte cher : on descend dans la grille, on
//  ouvre une chaîne, on fait RETOUR — et on doit retomber sur la tuile qu'on
//  venait de quitter, pas en haut à gauche. nav.js appelait toujours
//  focusFirst() au retour d'un écran → la place était perdue.
//
//  Ce module garde la DÉRIVATION DE CLÉ et le MAGASIN purs (aucun accès au
//  DOM), pour être testables sans navigateur (node --test). Il s'expose à la
//  fois comme global (DFT.focusKey, chargé par index.html) et comme module
//  CommonJS (require, pour les tests).
//
//  ES5 volontaire : les vieux WebKit de TV (Tizen/webOS) n'ont ni Map, ni
//  const/let, ni fonctions fléchées.
// =========================================================
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; }
  root.DFT = root.DFT || {};
  root.DFT.focusKey = api;
})(typeof window !== 'undefined' ? window : this, function () {
  'use strict';

  // Identifiant stable d'un focusable, résilient aux re-rendus :
  //   1. attribut data-fk explicite (posé par les rendus d'écran), sinon
  //   2. son texte normalisé, sinon
  //   3. null (l'appelant retombe sur un focus positionnel).
  function keyOf(el) {
    if (!el) return null;
    if (typeof el.getAttribute === 'function') {
      var explicit = el.getAttribute('data-fk');
      if (explicit) return explicit;
    }
    var text = el.textContent ? String(el.textContent).replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '') : '';
    return text ? 'txt:' + text : null;
  }

  // Mémoire de focus par écran. remember(scene, key) enregistre la dernière
  // clé focalisée d'un écran ; recall(scene) la relit (ou null). Adossé à un
  // objet simple (pas de Map) pour les vieux moteurs TV. `store` est
  // injectable pour les tests.
  function createFocusMemory(store) {
    store = store || {};
    return {
      remember: function (scene, key) { if (scene && key) { store[scene] = key; } },
      recall: function (scene) {
        return (scene && Object.prototype.hasOwnProperty.call(store, scene)) ? store[scene] : null;
      },
      forget: function (scene) { if (scene) { delete store[scene]; } }
    };
  }

  return { keyOf: keyOf, createFocusMemory: createFocusMemory };
});
