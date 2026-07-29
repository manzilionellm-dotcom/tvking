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
  var mediaHandler = null;                 // branché par l'écran lecteur (app.js)
  var scene = null;                        // écran courant (pour la mémoire de focus)
  var memory = (DFT.focusKey && DFT.focusKey.createFocusMemory)
    ? DFT.focusKey.createFocusMemory()     // { remember(scene,key), recall(scene) }
    : null;

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
    // Mémorise la place dans l'écran courant, pour la restaurer au retour.
    if (memory && scene && DFT.focusKey) memory.remember(scene, DFT.focusKey.keyOf(el));
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

  // Nom de touche média : chaîne KeyboardEvent.key (webOS/navigateur) ou
  // traduction du keyCode Tizen (DFT.keys.MEDIA). Retourne null sinon.
  function mediaName(e) {
    if (typeof e.key === 'string' && e.key.indexOf('Media') === 0) return e.key;
    if (DFT.keys && DFT.keys.MEDIA && DFT.keys.MEDIA[e.keyCode]) return DFT.keys.MEDIA[e.keyCode];
    return null;
  }

  function onKey(e) {
    var k = e.keyCode;
    if (DFT.isBack(k)) {
      e.preventDefault();
      if (backHandler) backHandler();
      return;
    }
    // Touches média (déjà déclarées par platform.js, jusqu'ici ignorées) :
    // routées vers l'écran lecteur quand il en a posé un gestionnaire.
    var mn = mediaName(e);
    if (mn && DFT.mediaKeys) {
      var action = DFT.mediaKeys.mediaKeyAction(mn);
      if (action && mediaHandler) { e.preventDefault(); mediaHandler(action); return; }
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

  // Entre dans un écran nommé : restaure le focus mémorisé pour cet écran
  // (RESTAURATION DU FOCUS), sinon retombe sur le 1er focusable. À appeler à
  // la place de focusFirst() quand on (re)affiche un écran.
  function enterScene(name) {
    scene = name || null;
    var list = focusables();
    if (!list.length) { current = null; return; }
    var key = (memory && scene) ? memory.recall(scene) : null;
    var target = null;
    if (key && DFT.focusKey) {
      for (var i = 0; i < list.length; i++) {
        if (DFT.focusKey.keyOf(list[i]) === key) { target = list[i]; break; }
      }
    }
    setFocus(target || list[0]);
  }

  return {
    init: init,
    setFocus: setFocus,
    focusFirst: focusFirst,
    enterScene: enterScene,
    onBack: function (fn) { backHandler = fn; },
    // Gestionnaire des touches média (play/pause/stop) — posé par l'écran
    // lecteur, remis à null en le quittant. onMedia(null) le débranche.
    onMedia: function (fn) { mediaHandler = fn || null; },
  };
})();
