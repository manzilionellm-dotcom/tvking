// =========================================================
//  app.js — Orchestration + écrans DeFew TV (Tizen / webOS)
// =========================================================
//  Flux : boot → MAC stable → heartbeat + statut.
//    • Abonnement inactif (essai expiré / gelé / banni) → écran ACTIVATION
//      (affiche la MAC en GROS, à donner au revendeur).
//    • Abonnement actif → on récupère la source poussée par le panel, on
//      charge les chaînes (Xtream ou M3U), et on affiche Direct + lecteur.
// =========================================================
window.DFT = window.DFT || {};

DFT.ui = (function () {
  function el(id) { return document.getElementById(id); }
  function show(id) { var e = el(id); if (e) e.style.display = 'flex'; }
  function hide(id) { var e = el(id); if (e) e.style.display = 'none'; }
  function setText(id, t) { var e = el(id); if (e) e.textContent = t; }

  function setBuffering(on) {
    var e = el('buffering');
    if (e) e.style.display = on ? 'flex' : 'none';
  }
  function setPlayerError(msg) {
    setBuffering(false);
    var e = el('player-error');
    if (e) { e.textContent = 'Erreur de lecture : ' + msg; e.style.display = 'block'; }
  }
  function clearPlayerError() {
    var e = el('player-error');
    if (e) e.style.display = 'none';
  }

  return {
    el: el, show: show, hide: hide, setText: setText,
    setBuffering: setBuffering, setPlayerError: setPlayerError,
    clearPlayerError: clearPlayerError,
  };
})();

DFT.app = (function () {
  var mac = '…';
  var channels = [];
  var byCat = {};       // catégorie -> [channels]
  var cats = [];        // ordre des catégories
  var currentCat = null;

  function screen(name) {
    var ids = ['screen-boot', 'screen-activation', 'screen-live', 'screen-player'];
    for (var i = 0; i < ids.length; i++) {
      var e = DFT.ui.el(ids[i]);
      if (e) e.style.display = (ids[i] === 'screen-' + name) ? 'flex' : 'none';
    }
  }

  // ---------- Boot ----------
  function boot() {
    DFT.platform && DFT.registerKeys();
    DFT.nav.init();
    screen('boot');
    DFT.device.getMac(function (m) {
      mac = m;
      DFT.ui.setText('act-mac', mac);
      var info = DFT.device.info();
      DFT.api.heartbeat(mac, info).then(check).catch(function () {
        // Hors-ligne : on tente quand même la source (cache éventuel côté CDN).
        check(null);
      });
    });
  }

  // ---------- Vérifie le statut puis route ----------
  function check(hb) {
    var active = hb && (hb.paid === true ||
      hb.status === 'active' || hb.status === 'trialActive' ||
      (hb.trial_until && hb.trial_until > Date.now()));
    if (active) {
      loadSource();
    } else {
      showActivation(hb);
    }
  }

  function showActivation(hb) {
    var msg = 'Donne cette adresse à ton revendeur pour activer ton abonnement.';
    if (hb) {
      if (hb.banned) msg = 'Cet appareil est bloqué. Contacte ton revendeur.';
      else if (hb.frozen) msg = 'Abonnement en pause. Contacte ton revendeur.';
      else if (hb.expired) msg = 'Ton essai est terminé. Active ton abonnement.';
    }
    DFT.ui.setText('act-msg', msg);
    screen('activation');
    DFT.nav.onBack(function () { /* écran racine : rien */ });
    DFT.nav.focusFirst();
  }

  // ---------- Charge la source poussée par le panel ----------
  function loadSource() {
    screen('boot');
    DFT.ui.setText('boot-text', 'Chargement de tes chaînes…');
    DFT.api.deviceSource(mac).then(function (res) {
      var list = (res && res.sources && res.sources.length)
        ? res.sources : (res && res.source ? [res.source] : []);
      if (!list.length) { showActivation({ expired: false }); return; }
      var src = list[0];
      var loader = (src.type === 'm3u') ? DFT.m3u.load(src) : DFT.xtream.load(src);
      loader.then(function (out) {
        channels = (out && out.channels) || [];
        if (!channels.length) {
          DFT.ui.setText('act-msg', 'Source vide ou injoignable. Vérifie avec ton revendeur.');
          screen('activation'); DFT.nav.focusFirst(); return;
        }
        indexChannels();
        renderLive();
      }).catch(function () {
        DFT.ui.setText('act-msg', 'Impossible de charger la source. Réessaie plus tard.');
        screen('activation'); DFT.nav.focusFirst();
      });
    }).catch(function () {
      showActivation(null);
    });
  }

  function indexChannels() {
    byCat = {}; cats = [];
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i].category || 'Autres';
      if (!byCat[c]) { byCat[c] = []; cats.push(c); }
      byCat[c].push(channels[i]);
    }
    currentCat = cats[0] || null;
  }

  // ---------- Écran DIRECT (catégories + grille) ----------
  function renderLive() {
    screen('live');
    var catBox = DFT.ui.el('cat-list');
    var grid = DFT.ui.el('chan-grid');
    catBox.innerHTML = '';
    for (var i = 0; i < cats.length; i++) {
      catBox.appendChild(catRow(cats[i]));
    }
    renderGrid();
    DFT.nav.onBack(function () { screen('live'); });
    DFT.nav.focusFirst();
  }

  function catRow(name) {
    var d = document.createElement('div');
    d.className = 'cat focusable' + (name === currentCat ? ' active' : '');
    d.textContent = name;
    d.onclick = function () {
      currentCat = name;
      var all = document.querySelectorAll('#cat-list .cat');
      for (var i = 0; i < all.length; i++) all[i].classList.remove('active');
      d.classList.add('active');
      renderGrid();
    };
    return d;
  }

  function renderGrid() {
    var grid = DFT.ui.el('chan-grid');
    grid.innerHTML = '';
    var list = byCat[currentCat] || [];
    for (var i = 0; i < list.length; i++) {
      grid.appendChild(chanTile(list[i]));
    }
  }

  function chanTile(ch) {
    var d = document.createElement('div');
    d.className = 'tile focusable';
    var logo = ch.logo
      ? '<div class="tile-logo" style="background-image:url(\'' + ch.logo.replace(/'/g, '') + '\')"></div>'
      : '<div class="tile-logo tile-logo-empty">' + (ch.name || '?').charAt(0) + '</div>';
    d.innerHTML = logo + '<div class="tile-name">' + escapeHtml(ch.name) + '</div>';
    d.onclick = function () { openPlayer(ch); };
    return d;
  }

  // ---------- Lecteur plein écran ----------
  function openPlayer(ch) {
    screen('player');
    DFT.ui.clearPlayerError();
    DFT.ui.setText('player-title', ch.name || '');
    DFT.ui.setBuffering(true);
    DFT.player.play(ch.url);
    DFT.nav.onBack(function () {
      DFT.player.stop();
      renderLive();
    });
  }

  function escapeHtml(s) {
    return String(s || '').replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // Bouton « rafraîchir » de l'écran activation.
  function refresh() {
    screen('boot');
    DFT.ui.setText('boot-text', 'Vérification…');
    DFT.api.heartbeat(mac, DFT.device.info()).then(check).catch(function () { check(null); });
  }

  return { boot: boot, refresh: refresh };
})();

window.addEventListener('load', function () { DFT.app.boot(); });
