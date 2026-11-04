// =========================================================
//  app.js — Orchestration + écrans ZUNO (Tizen / webOS)
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
  var currentScreen = 'boot';
  var previousScreen = 'activation';
  var mac = '…';
  var channels = [];
  var byCat = Object.create(null);       // catégorie -> [channels]
  var cats = [];        // ordre des catégories
  var currentCat = null;

  function screen(name) {
    currentScreen = name;
    var ids = ['screen-boot', 'screen-activation', 'screen-live', 'screen-player', 'screen-about', 'screen-exit'];
    for (var i = 0; i < ids.length; i++) {
      var e = DFT.ui.el(ids[i]);
      if (e) e.style.display = (ids[i] === 'screen-' + name) ? 'flex' : 'none';
    }
  }

  // ---------- Boot ----------
  function boot() {
    DFT.platform && DFT.registerKeys();
    DFT.nav.init();
    DFT.nav.onBack(requestExit);
    // Le gel ou retrait d’une licence doit aussi être respecté pendant la lecture.
    window.setInterval(function () {
      if (mac === '…' || document.hidden || (currentScreen !== 'live' && currentScreen !== 'player')) return;
      DFT.api.status(mac).then(function (status) {
        if (!canUse(status)) { DFT.player.stop(); channels = []; showActivation(status); }
      }).catch(function () { /* conserver l’écran actuel lors d’une panne passagère */ });
    }, 60000);
    screen('boot');
    DFT.device.getMac(function (m) {
      mac = m;
      DFT.ui.setText('act-mac', mac);
      var info = DFT.device.info();
      DFT.api.heartbeat(mac, info).then(check).catch(function () {
        // Hors-ligne : écran réseau avec possibilité de réessayer.
        check(null);
      });
    });
  }

  // ---------- Vérifie le statut puis route ----------
  function check(hb) {
    // Un statut « active » peut aussi accompagner un essai expiré : les
    // blocages explicites doivent toujours primer sur le champ paid/status.
    var active = canUse(hb);
    if (active) {
      loadSource();
    } else {
      showActivation(hb);
    }
  }

  function canUse(hb) {
    return !!hb && !hb.banned && !hb.frozen &&
      hb.status !== 'banned' && hb.status !== 'frozen' &&
      (hb.paid === true || (hb.expired !== true && Number(hb.trial_until) > Date.now()));
  }

  function showActivation(hb) {
    var msg = hb ? 'Associez cet identifiant à votre licence et à vos propres sources depuis le panel.' : 'Connexion au service impossible. Vérifiez le réseau puis réessayez.';
    if (hb) {
      if (hb.banned) msg = 'Cet appareil est bloqué. Contacte ton revendeur.';
      else if (hb.frozen) msg = 'Abonnement en pause. Contacte ton revendeur.';
      else if (hb.expired) msg = 'Ton essai est terminé. Active ton abonnement.';
    }
    DFT.ui.setText('act-msg', msg);
    screen('activation');
    DFT.nav.onBack(requestExit);
    DFT.nav.focusFirst();
  }

  // ---------- Charge la source poussée par le panel ----------
  function loadSource() {
    screen('boot');
    DFT.ui.setText('boot-text', 'Chargement de tes chaînes…');
    DFT.api.deviceSource(mac).then(function (res) {
      var list = (res && res.sources && res.sources.length)
        ? res.sources : (res && res.source ? [res.source] : []);
      if (!list.length) {
        showActivation({});
        DFT.ui.setText('act-msg', res && res.blocked ? 'Licence indisponible : ' + res.blocked : 'Aucune source assignée. Ajoutez votre source personnelle dans le panel.');
        return;
      }
      // Charger toutes les sources du panel ; une panne isolée ne masque pas les autres.
      var loader = Promise.all(list.map(function (src) {
        var task = src.type === 'm3u' ? DFT.m3u.load(src) :
          src.type === 'xtream' ? DFT.xtream.load(src) : Promise.reject(new Error('Type inconnu'));
        return task.catch(function () { return { channels: [] }; });
      })).then(function (results) {
        return { channels: [].concat.apply([], results.map(function (result) { return result.channels || []; })) };
      });
      loader.then(function (out) {
        channels = (out && out.channels) || [];
        if (!channels.length) {
          DFT.ui.setText('act-msg', 'Source vide ou injoignable. Vérifie avec ton revendeur.');
          screen('activation'); DFT.nav.onBack(requestExit); DFT.nav.focusFirst(); return;
        }
        indexChannels();
        renderLive();
      }).catch(function () {
        DFT.ui.setText('act-msg', 'Impossible de charger la source. Réessaie plus tard.');
        screen('activation'); DFT.nav.onBack(requestExit); DFT.nav.focusFirst();
      });
    }).catch(function () {
      showActivation(null);
    });
  }

  function indexChannels() {
    byCat = Object.create(null); cats = [];
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
    DFT.nav.onBack(requestExit);
    DFT.nav.focusFirst();
  }

  function catRow(name) {
    var d = document.createElement('div');
    d.className = 'cat focusable' + (name === currentCat ? ' active' : '');
    d.textContent = name;
    d.tabIndex = 0; d.setAttribute('role', 'button');
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
    d.tabIndex = 0; d.setAttribute('role', 'button');
    // Aucune donnée de playlist n’est injectée comme HTML (nom/logo non fiables).
    var logo = document.createElement('div');
    logo.className = 'tile-logo tile-logo-empty';
    logo.textContent = (ch.name || '?').charAt(0);
    if (/^https?:\/\//i.test(ch.logo || '')) {
      logo.className = 'tile-logo';
      logo.style.backgroundImage = 'url(' + JSON.stringify(ch.logo) + ')';
      logo.textContent = '';
    }
    var name = document.createElement('div');
    name.className = 'tile-name'; name.textContent = ch.name || 'Chaîne';
    d.appendChild(logo); d.appendChild(name);
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

  // Bouton « rafraîchir » de l'écran activation.
  function refresh() {
    screen('boot');
    DFT.ui.setText('boot-text', 'Vérification…');
    DFT.api.heartbeat(mac, DFT.device.info()).then(check).catch(function () { check(null); });
  }

  function requestExit() {
    previousScreen = currentScreen;
    screen('exit'); DFT.nav.onBack(cancelExit); DFT.nav.focusFirst();
  }
  function cancelExit() {
    screen(previousScreen);
    DFT.nav.onBack(previousScreen === 'player' ? function () { DFT.player.stop(); renderLive(); } : requestExit);
    DFT.nav.focusFirst();
  }
  function exit() {
    DFT.player.stop();
    if (DFT.platform === 'tizen') tizen.application.getCurrentApplication().exit();
    else cancelExit();
  }
  function showAbout() { screen('about'); DFT.nav.onBack(closeAbout); DFT.nav.focusFirst(); }
  function closeAbout() { showActivation({}); }
  // Arrêt au passage en arrière-plan : pas de son invisible ni reprise imposée.
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) {
      DFT.player.stop();
      if (currentScreen === 'player' || (currentScreen === 'exit' && previousScreen === 'player')) renderLive();
    }
  });
  return { boot: boot, refresh: refresh, canUse: canUse, showAbout: showAbout,
    closeAbout: closeAbout, cancelExit: cancelExit, exit: exit };

})();

window.addEventListener('load', function () { DFT.app.boot(); });
