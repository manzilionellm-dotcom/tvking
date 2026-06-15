// =========================================================
//  nav.js — Navigation à la télécommande (D-pad) générique
// =========================================================
//  Navigation SPATIALE : à partir de l'élément focalisé, la flèche choisit
//  l'élément focusable le plus proche dans la direction visée (par géométrie).
//  Marche pour les listes ET les grilles sans configuration. « OK » clique,
//  « Retour » remonte d'écran (géré par app.js via DFT.nav.onBack).
// =========================================================
window.DFT = window.DFT || {};

DFT.nav = (function () {
  var current = null;
  var backHandler = null;

  function focusables() {
    var nodes = document.querySelectorAll('.focusable');
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.offsetParent !== null) out.push(el); // visible uniquement
    }
    return out;
  }

  function setFocus(el) {
    if (!el) return;
    if (current && current !== el) current.classList.remove('focused');
    current = el;
    el.classList.add('focused');
    if (el.scrollIntoView) {
      try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) { el.scrollIntoView(); }
    }
  }

  function center(el) {
    var r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  // Trouve le meilleur candidat dans la direction (dx,dy).
  function move(dir) {
    var list = focusables();
    if (!list.length) return;
    if (!current || list.indexOf(current) === -1) { setFocus(list[0]); return; }
    var c = center(current);
    var best = null, bestScore = Infinity;
    for (var i = 0; i < list.length; i++) {
      if (list[i] === current) continue;
      var p = center(list[i]);
      var dx = p.x - c.x, dy = p.y - c.y;
      var ok = false, primary = 0, secondary = 0;
      if (dir === 'left')  { ok = dx < -4; primary = -dx; secondary = Math.abs(dy); }
      if (dir === 'right') { ok = dx > 4;  primary = dx;  secondary = Math.abs(dy); }
      if (dir === 'up')    { ok = dy < -4; primary = -dy; secondary = Math.abs(dx); }
      if (dir === 'down')  { ok = dy > 4;  primary = dy;  secondary = Math.abs(dx); }
      if (!ok) continue;
      // Score : on privilégie l'alignement (secondary) puis la proximité.
      var score = secondary * 2 + primary;
      if (score < bestScore) { bestScore = score; best = list[i]; }
    }
    if (best) setFocus(best);
  }

  function activate() {
    if (current && typeof current.click === 'function') current.click();
  }

  function onKey(e) {
    var k = e.keyCode;
    if (DFT.isBack(k)) {
      e.preventDefault();
      if (backHandler) backHandler();
      return;
    }
    switch (k) {
      case DFT.keys.LEFT:  e.preventDefault(); move('left'); break;
      case DFT.keys.RIGHT: e.preventDefault(); move('right'); break;
      case DFT.keys.UP:    e.preventDefault(); move('up'); break;
      case DFT.keys.DOWN:  e.preventDefault(); move('down'); break;
      case DFT.keys.ENTER: e.preventDefault(); activate(); break;
      default: break;
    }
  }

  function init() {
    document.addEventListener('keydown', onKey, false);
  }

  // Met le focus sur le 1er focusable d'un conteneur (après un changement d'écran).
  function focusFirst() {
    var list = focusables();
    if (list.length) setFocus(list[0]);
    else current = null;
  }

  return {
    init: init,
    setFocus: setFocus,
    focusFirst: focusFirst,
    onBack: function (fn) { backHandler = fn; },
  };
})();
