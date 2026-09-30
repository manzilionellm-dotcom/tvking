// =========================================================
//  remote_page.dart — La page que le téléphone affiche
// =========================================================
//  UNE SEULE page, sans rien à installer, sans rien à télécharger
//  d'Internet (pas de police, pas de script extérieur). Elle est
//  servie par la box elle-même. Les couleurs reprennent TvTokens
//  (noir profond, or champagne, ivoire) pour qu'on reconnaisse Zuno.
//
//  Le jeton N'EST PAS écrit dans cette page : les boutons appellent
//  `pair`, `cmd` et `status` en relatif. Seule l'adresse du QR
//  (déjà connue du téléphone qui l'a ouverte) porte le secret.
// =========================================================

/// Page télécommande. Constante : aucun nom, aucune adresse, aucun
/// jeton n'y est injecté.
String remoteControlPageHtml() => r'''<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer">
<title>Zuno — Télécommande</title>
<style>
  :root {
    --bg: #070708;
    --card: #141418;
    --text: #F0EDE9;
    --muted: #9C9BA4;
    --line: #2B2B34;
    --accent: #C99A3A;
    --bright: #F2CF7A;
    --on: #14100A;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body {
    margin: 0; padding: 0; background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    min-height: 100%;
  }
  body {
    padding: max(16px, env(safe-area-inset-top)) 16px max(20px, env(safe-area-inset-bottom));
    touch-action: manipulation;
  }
  main { max-width: 420px; margin: 0 auto; }
  h1 { font-size: 22px; font-weight: 750; letter-spacing: 0.04em; margin: 0; }
  h1 b { color: var(--bright); font-weight: 750; }
  .sub { color: var(--muted); font-size: 14px; margin: 6px 0 14px; line-height: 1.35; }
  #left { color: var(--bright); font-size: 14px; font-weight: 650; min-height: 1.2em; }
  #msg { color: var(--muted); font-size: 14px; min-height: 1.2em; margin: 4px 0 12px; }
  .dpad {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    grid-template-areas: ". up ." "left ok right" ". down .";
    gap: 10px; width: min(100%, 320px); margin: 8px auto 14px;
  }
  .up { grid-area: up; } .down { grid-area: down; }
  .left { grid-area: left; } .right { grid-area: right; } .ok { grid-area: ok; }
  button {
    font: inherit; color: var(--text); background: var(--card);
    border: 1px solid var(--line); border-radius: 14px;
    min-height: 64px; font-size: 16px; font-weight: 650;
    user-select: none; touch-action: manipulation;
  }
  button:active:not(:disabled) { border-color: var(--accent); color: var(--bright); }
  button:disabled { opacity: 0.35; }
  button.ok, button.go {
    background: var(--accent); color: var(--on); border-color: var(--accent);
    font-weight: 800;
  }
  .row { display: flex; gap: 10px; margin-bottom: 10px; }
  .row button { flex: 1; }
  label { display: block; font-size: 13px; color: var(--muted); margin: 16px 0 8px; }
  input {
    width: 100%; font: inherit; font-size: 18px; color: var(--text);
    background: var(--card); border: 1px solid var(--line); border-radius: 14px;
    padding: 14px 16px;
  }
  input:focus { outline: 2px solid var(--accent); border-color: var(--accent); }
  .hint { color: var(--muted); font-size: 13px; line-height: 1.4; margin-top: 8px; }
</style>
</head>
<body>
<main>
  <h1>Zuno <b>télécommande</b></h1>
  <p class="sub">Même Wi-Fi que la box. Rien à installer.</p>
  <div id="left"></div>
  <div id="msg">Connexion à la box…</div>
  <div class="dpad">
    <button type="button" class="up" id="b-up" disabled>Haut</button>
    <button type="button" class="left" id="b-left" disabled>Gauche</button>
    <button type="button" class="ok" id="b-ok" disabled>OK</button>
    <button type="button" class="right" id="b-right" disabled>Droite</button>
    <button type="button" class="down" id="b-down" disabled>Bas</button>
  </div>
  <div class="row">
    <button type="button" id="b-back" disabled>Retour</button>
  </div>
  <div class="row">
    <button type="button" id="b-ch-down" disabled>Chaîne −</button>
    <button type="button" id="b-ch-up" disabled>Chaîne +</button>
  </div>
  <div class="row">
    <button type="button" id="b-vol-down" disabled>Volume −</button>
    <button type="button" id="b-vol-up" disabled>Volume +</button>
  </div>
  <label for="q">Recherche — ouvre Recherche sur la box, puis tape ici</label>
  <input id="q" maxlength="240" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="search" placeholder="Nom de la chaîne" disabled>
  <div class="row" style="margin-top:10px">
    <button type="button" class="go" id="b-send" disabled>Envoyer le texte</button>
    <button type="button" id="b-clear" disabled>Effacer</button>
  </div>
  <p class="hint">Maintiens Haut, Bas, Gauche, Droite, volume ou chaîne pour répéter. Le code affiché sur la box expire tout seul.</p>
</main>
<script>
(function () {
  var locked = true;
  var timer = null;
  function msg(t) { document.getElementById('msg').textContent = t; }
  function setLocked(on) {
    locked = on;
    var nodes = document.querySelectorAll('button, input');
    for (var i = 0; i < nodes.length; i++) nodes[i].disabled = on;
  }
  function showLeft(s) {
    s = s < 0 ? 0 : s;
    var m = Math.floor(s / 60);
    var ss = String(s % 60);
    if (ss.length < 2) ss = '0' + ss;
    document.getElementById('left').textContent = 'Expire dans ' + m + ' min ' + ss + ' s';
  }
  function send(action, text) {
    if (locked && action !== 'pair') return;
    var body = (text === undefined) ? {a: action} : {a: action, t: text};
    return fetch('cmd', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', 'X-Zuno-Remote': '1'},
      credentials: 'same-origin',
      cache: 'no-store',
      body: JSON.stringify(body)
    }).then(function (r) {
      if (r.status === 410) { msg('Code expiré. Regarde la box et scanne le nouveau QR.'); setLocked(true); }
      else if (r.status === 401 || r.status === 403) { msg('Cette télécommande n’est plus appairée.'); setLocked(true); }
      return r;
    }).catch(function () { msg('La box ne répond plus. Même Wi-Fi ?'); });
  }
  function bindTap(id, action) {
    document.getElementById(id).addEventListener('click', function () { send(action); });
  }
  function bindHold(id, action) {
    var el = document.getElementById(id);
    var repeat = null;
    function stop() { if (repeat) { clearInterval(repeat); repeat = null; } }
    el.addEventListener('pointerdown', function (e) {
      if (e.button && e.button !== 0) return;
      e.preventDefault();
      send(action);
      stop();
      repeat = setInterval(function () { send(action); }, 180);
    });
    el.addEventListener('pointerup', stop);
    el.addEventListener('pointercancel', stop);
    el.addEventListener('pointerleave', stop);
    el.addEventListener('keydown', function (e) {
      if (e.repeat) return;
      if (e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      send(action);
    });
  }
  bindHold('b-up', 'up');
  bindHold('b-down', 'down');
  bindHold('b-left', 'left');
  bindHold('b-right', 'right');
  bindTap('b-ok', 'ok');
  bindTap('b-back', 'back');
  bindHold('b-ch-up', 'ch_up');
  bindHold('b-ch-down', 'ch_down');
  bindHold('b-vol-up', 'vol_up');
  bindHold('b-vol-down', 'vol_down');
  var q = document.getElementById('q');
  var qtimer = null;
  q.addEventListener('input', function () {
    if (qtimer) clearTimeout(qtimer);
    var value = q.value;
    qtimer = setTimeout(function () { send('query', value); }, 120);
  });
  document.getElementById('b-send').addEventListener('click', function () { send('query', q.value); });
  document.getElementById('b-clear').addEventListener('click', function () {
    q.value = '';
    send('query', '');
    q.focus();
  });
  function poll() {
    if (timer) clearTimeout(timer);
    fetch('status', {credentials: 'same-origin', cache: 'no-store'}).then(function (r) {
      if (r.status === 410) { msg('Code expiré. Regarde la box.'); setLocked(true); return; }
      if (!r.ok) { msg('Télécommande coupée.'); setLocked(true); return; }
      return r.json().then(function (j) { showLeft(j.left | 0); });
    }).catch(function () { msg('La box ne répond plus. Même Wi-Fi ?'); })
      .then(function () { timer = setTimeout(poll, 2000); });
  }
  fetch('pair', {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Zuno-Remote': '1'},
    credentials: 'same-origin',
    cache: 'no-store',
    body: '{}'
  }).then(function (r) {
    if (r.status === 403) { msg('Un autre téléphone est déjà connecté. Sur la box : Nouveau code.'); return; }
    if (r.status === 410) { msg('Code expiré. Regarde la box.'); return; }
    if (!r.ok) { msg('Connexion refusée.'); return; }
    setLocked(false);
    msg('Connecté. Tu pilotes la box.');
    return r.json().then(function (j) { showLeft(j.left | 0); poll(); });
  }).catch(function () { msg('Impossible de joindre la box. Même Wi-Fi ?'); });
})();
</script>
</body>
</html>
''';
