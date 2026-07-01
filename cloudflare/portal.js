// =========================================================
//  portal.js — « Mon espace » : gérer sa playlist (façon IBO Player Pro)
// =========================================================
//  Page cliente servie sur /mon-espace par worker.js (import portalHtml).
//  Le client entre SA MAC → il voit sa playlist, peut l'AJOUTER / MODIFIER /
//  SUPPRIMER lui-même (M3U ou Xtream). Une source posée par le PANEL (client
//  payant) reste VERROUILLÉE (lecture seule) → protège les payants.
//
//  Back-end : /api/self-source/:mac  (GET | POST | DELETE) dans worker.js.
//  Aucune donnée sensible n'est renvoyée (le mot de passe Xtream n'est JAMAIS
//  relu). Même origine → pas de CORS. noindex (outil client, pas du marketing).
//
//  IMPORTANT : ce fichier est un VRAI module JS importé tel quel (pas ré-échappé
//  comme landing.js). Le JS de la PAGE évite volontairement les backticks / ${}
//  (concaténation par +) pour ne pas casser le template literal extérieur.
// =========================================================

export function portalHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Mon espace — Gérer ma playlist | 7 MOTION</title>
<meta name="robots" content="noindex, nofollow" />
<meta name="theme-color" content="#0c0c0e" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/manifest.webmanifest" />
<style>
  :root{
    --bg:#0c0c0e; --bg-soft:#111115;
    --panel:rgba(255,255,255,.035); --panel-2:rgba(255,255,255,.06);
    --line:rgba(255,255,255,.09); --line-gold:rgba(214,176,94,.35);
    --gold:#d8b766; --gold-bright:#ecd08a; --red:#e0202e;
    --green:#3ecf8e; --text:#d9d6ce; --muted:#8f8c85;
    --radius:20px;
    --serif:"Hoefler Text","Iowan Old Style",Garamond,"Palatino Linotype","Times New Roman",serif;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--text);font-family:var(--sans);line-height:1.6;
    -webkit-font-smoothing:antialiased;min-height:100vh;
    background-image:radial-gradient(120% 80% at 50% -10%,rgba(216,183,102,.06),transparent 55%),
      radial-gradient(90% 60% at 85% 8%,rgba(224,32,46,.03),transparent 60%);
    background-attachment:fixed}
  a{color:inherit;text-decoration:none}
  .wrap{max-width:720px;margin:0 auto;padding:0 20px}
  header.nav{position:sticky;top:0;z-index:50;background:rgba(5,5,6,.72);
    backdrop-filter:blur(16px);border-bottom:1px solid var(--line)}
  .nav-in{display:flex;align-items:center;justify-content:space-between;height:66px;
    max-width:720px;margin:0 auto;padding:0 20px}
  .logo{font-weight:800;font-size:20px;letter-spacing:2px}
  .logo b{color:var(--red)}
  .nav-back{color:var(--muted);font-size:14px}
  .nav-back:hover{color:var(--text)}
  main{padding:44px 0 90px}
  .eyebrow{display:inline-block;color:var(--gold);font-size:12px;font-weight:700;
    letter-spacing:3px;text-transform:uppercase;margin-bottom:14px}
  h1{font-family:var(--serif);font-weight:600;font-size:clamp(28px,6vw,40px);
    line-height:1.1;letter-spacing:-.4px}
  h2{font-family:var(--serif);font-weight:600;font-size:22px;letter-spacing:-.3px}
  .lead{color:var(--muted);font-size:16px;margin-top:12px}
  .card{background:linear-gradient(180deg,var(--panel-2),var(--panel));
    border:1px solid var(--line);border-radius:var(--radius);padding:26px;margin-top:22px}
  .card.gold{border-color:var(--line-gold)}
  .btn{display:inline-flex;align-items:center;justify-content:center;gap:9px;
    padding:15px 26px;border-radius:999px;font-weight:800;font-size:15.5px;
    cursor:pointer;border:none;transition:.22s ease;font-family:var(--sans);width:100%}
  .btn:active{transform:scale(.98)}
  .btn-gold{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    box-shadow:0 10px 30px rgba(216,183,102,.26)}
  .btn-gold:hover{transform:translateY(-1px)}
  .btn-ghost{background:transparent;color:var(--text);border:1px solid var(--line)}
  .btn-ghost:hover{border-color:var(--gold);color:var(--gold-bright)}
  .btn-danger{background:transparent;color:#e88;border:1px solid rgba(224,32,46,.4)}
  .btn-danger:hover{background:rgba(224,32,46,.1)}
  .btn-row{display:flex;gap:12px;flex-wrap:wrap;margin-top:8px}
  .btn-row .btn{width:auto;flex:1;min-width:130px;padding:13px 20px;font-size:14.5px}
  label{display:block;color:var(--muted);font-size:13px;margin:16px 0 7px;font-weight:600}
  input{width:100%;background:rgba(0,0,0,.4);border:1px solid var(--line);color:var(--text);
    border-radius:13px;padding:15px 17px;font-size:16px;font-family:var(--sans);letter-spacing:.3px}
  input:focus{outline:none;border-color:var(--gold)}
  .hint{color:var(--muted);font-size:13px;margin-top:12px}
  .row{display:flex;justify-content:space-between;align-items:center;gap:14px;
    padding:13px 0;border-bottom:1px solid var(--line)}
  .row:last-child{border-bottom:none}
  .row .k{color:var(--muted);font-size:13.5px}
  .row .v{font-weight:700;font-size:14.5px;text-align:right;word-break:break-word}
  .badge{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:800;
    letter-spacing:.5px;padding:5px 12px;border-radius:999px;text-transform:uppercase}
  .badge.ok{background:rgba(62,207,142,.14);color:var(--green);border:1px solid rgba(62,207,142,.3)}
  .badge.lock{background:rgba(216,183,102,.14);color:var(--gold-bright);border:1px solid var(--line-gold)}
  .badge.wait{background:rgba(255,255,255,.06);color:var(--muted);border:1px solid var(--line)}
  .pl-name{font-weight:800;font-size:17px}
  .pl-url{color:var(--muted);font-size:13.5px;margin-top:4px;word-break:break-all}
  .seg{display:flex;gap:8px;background:rgba(0,0,0,.3);border:1px solid var(--line);
    border-radius:13px;padding:5px;margin-top:6px}
  .seg button{flex:1;background:transparent;border:none;color:var(--muted);font-weight:700;
    font-size:14px;padding:11px;border-radius:9px;cursor:pointer;font-family:var(--sans)}
  .seg button.on{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606}
  .msg{margin-top:16px;padding:13px 16px;border-radius:13px;font-size:14px;display:none}
  .msg.show{display:block}
  .msg.ok{background:rgba(62,207,142,.1);border:1px solid rgba(62,207,142,.3);color:#bfe}
  .msg.err{background:rgba(224,32,46,.1);border:1px solid rgba(224,32,46,.35);color:#f9b9be}
  .hide{display:none !important}
  .center{text-align:center}
  .spin{display:inline-block;width:18px;height:18px;border:2px solid rgba(255,255,255,.25);
    border-top-color:#1c1606;border-radius:50%;animation:sp .7s linear infinite;vertical-align:-3px}
  @keyframes sp{to{transform:rotate(360deg)}}
  .foot{color:var(--muted);font-size:12.5px;text-align:center;margin-top:34px;line-height:1.7}
</style>
</head>
<body>
<header class="nav"><div class="nav-in">
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <a class="nav-back" href="/">&#8592; Accueil</a>
</div></header>

<main><div class="wrap">

  <!-- ÉCRAN 1 : connexion par MAC -->
  <section id="login">
    <span class="eyebrow">Mon espace</span>
    <h1>Gérez votre playlist</h1>
    <p class="lead">Entrez l'adresse de votre appareil (elle s'affiche sur l'écran d'accueil de l'app, ou dans « À&nbsp;propos&nbsp;»). Vous pouvez ensuite ajouter, changer ou retirer votre playlist vous-même, à tout moment.</p>
    <div class="card">
      <label for="macIn">Adresse de l'appareil (MAC)</label>
      <input id="macIn" type="text" inputmode="text" autocomplete="off" autocapitalize="characters"
        spellcheck="false" placeholder="MK:XX:XX:XX:XX:XX" maxlength="23" />
      <div style="margin-top:18px"></div>
      <button class="btn btn-gold" id="loginBtn">Ouvrir mon espace</button>
      <div id="loginMsg" class="msg err"></div>
      <p class="hint">Aucun mot de passe. Votre adresse suffit — elle est unique à votre appareil.</p>
    </div>
  </section>

  <!-- ÉCRAN 2 : tableau de bord -->
  <section id="dash" class="hide">
    <span class="eyebrow">Mon espace</span>
    <h1>Votre appareil</h1>

    <div class="card">
      <div class="row"><span class="k">Adresse (MAC)</span><span class="v" id="dMac">—</span></div>
      <div class="row"><span class="k">Statut</span><span class="v" id="dStatus">—</span></div>
    </div>

    <!-- Playlist actuelle -->
    <div class="card" id="plCard">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px">
        <h2>Ma playlist</h2>
        <span id="plBadge" class="badge wait">—</span>
      </div>
      <div id="plBody" style="margin-top:14px"></div>
      <div class="btn-row" id="plActions"></div>
      <div id="lockNote" class="hint hide">Cette playlist a été mise en place par votre conseiller : elle est protégée. Pour la modifier, écrivez au support — on s'en occupe tout de suite.</div>
    </div>

    <!-- Ajouter / modifier -->
    <div class="card gold hide" id="addCard">
      <h2 id="addTitle">Ajouter ma playlist</h2>
      <div class="seg">
        <button type="button" id="tabM3u" class="on">Lien M3U</button>
        <button type="button" id="tabXc">Xtream (XC)</button>
      </div>

      <label for="fName">Nom (au choix)</label>
      <input id="fName" type="text" placeholder="Ma playlist" maxlength="60" />

      <!-- M3U -->
      <div id="formM3u">
        <label for="fM3u">Lien M3U</label>
        <input id="fM3u" type="url" inputmode="url" autocomplete="off" spellcheck="false"
          placeholder="http://…/get.php?username=…&password=…&type=m3u_plus" />
      </div>

      <!-- Xtream -->
      <div id="formXc" class="hide">
        <label for="fHost">Serveur (host)</label>
        <input id="fHost" type="url" inputmode="url" autocomplete="off" spellcheck="false"
          placeholder="http://mon-serveur.com:8080" />
        <label for="fUser">Utilisateur</label>
        <input id="fUser" type="text" autocomplete="off" spellcheck="false" placeholder="username" />
        <label for="fPass">Mot de passe</label>
        <input id="fPass" type="text" autocomplete="off" spellcheck="false" placeholder="password" />
      </div>

      <label for="fEpg">Guide TV / EPG (optionnel)</label>
      <input id="fEpg" type="url" inputmode="url" autocomplete="off" spellcheck="false"
        placeholder="http://…/xmltv.php?username=…  (facultatif)" />

      <div style="margin-top:20px"></div>
      <button class="btn btn-gold" id="saveBtn">Enregistrer ma playlist</button>
      <button class="btn btn-ghost hide" id="cancelBtn" style="margin-top:10px">Annuler</button>
      <div id="saveMsg" class="msg"></div>
      <p class="hint">Après enregistrement, ouvrez (ou redémarrez) l'app : vos chaînes apparaissent automatiquement.</p>
    </div>

    <div class="btn-row" style="margin-top:24px">
      <button class="btn btn-ghost" id="refreshBtn">Rafraîchir</button>
      <button class="btn btn-ghost" id="logoutBtn">Changer d'appareil</button>
    </div>

    <p class="foot">7&nbsp;MOTION est un lecteur multimédia. Vous fournissez votre propre playlist ;
      aucun contenu n'est fourni par le service. Besoin d'aide ? Un conseiller reste disponible.</p>
  </div></section>

</div></main>

<script>
(function(){
  "use strict";
  var MAC_RX = /^MK(:[0-9A-F]{2}){5}$/;
  var api = function(mac){ return "/api/self-source/" + encodeURIComponent(mac); };
  var $ = function(id){ return document.getElementById(id); };
  var state = { mac:null, mode:"m3u", editing:false };

  function normMac(v){
    return String(v||"").toUpperCase().replace(/\\s+/g,"").replace(/-/g,":");
  }
  function showMsg(el, kind, text){
    el.className = "msg " + kind + " show";
    el.textContent = text;
  }
  function hideMsg(el){ el.className = "msg"; el.textContent = ""; }
  function esc(s){ return String(s==null?"":s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }

  // ---- Écran login -------------------------------------------------------
  function doLogin(){
    var mac = normMac($("macIn").value);
    $("macIn").value = mac;
    if(!MAC_RX.test(mac)){
      showMsg($("loginMsg"),"err","Adresse invalide. Format attendu : MK:XX:XX:XX:XX:XX (copiez-la depuis l'app).");
      return;
    }
    hideMsg($("loginMsg"));
    state.mac = mac;
    try{ localStorage.setItem("sm_mac", mac); }catch(e){}
    openDash();
  }

  function openDash(){
    $("login").classList.add("hide");
    $("dash").classList.remove("hide");
    $("dMac").textContent = state.mac;
    load();
  }

  // ---- Charger l'état de la playlist -------------------------------------
  function load(){
    $("dStatus").textContent = "Chargement…";
    $("plBody").innerHTML = "<p class='hint' style='margin-top:0'>Chargement…</p>";
    $("plActions").innerHTML = "";
    fetch(api(state.mac), { headers:{ "Accept":"application/json" } })
      .then(function(r){ return r.json().catch(function(){ return {}; }); })
      .then(render)
      .catch(function(){
        $("dStatus").textContent = "Hors ligne";
        $("plBody").innerHTML = "<p class='hint' style='margin-top:0'>Connexion impossible. Réessayez dans un instant.</p>";
      });
  }

  function render(d){
    var badge = $("plBadge"), body = $("plBody"), actions = $("plActions");
    actions.innerHTML = ""; $("lockNote").classList.add("hide");
    hideForm();

    if(!d || d.ok !== true){
      $("dStatus").textContent = "—";
      badge.className = "badge wait"; badge.textContent = "Indisponible";
      body.innerHTML = "<p class='hint' style='margin-top:0'>Impossible de lire l'état pour le moment.</p>";
      return;
    }

    if(!d.hasSource){
      $("dStatus").innerHTML = "<span class='badge wait'>En attente de playlist</span>";
      badge.className = "badge wait"; badge.textContent = "Aucune";
      body.innerHTML = "<p class='hint' style='margin-top:0'>Aucune playlist enregistrée. Ajoutez la vôtre ci-dessous en quelques secondes.</p>";
      addAction("Ajouter ma playlist","btn-gold", function(){ openForm(false); });
      // Ouvre directement le formulaire d'ajout (plus rapide).
      openForm(false);
      return;
    }

    var s = d.source || {};
    var kind = s.type === "xtream" ? "Xtream (XC)" : "Lien M3U";
    var url = s.type === "xtream" ? (s.server_url || "") : (s.m3u_url || "");
    body.innerHTML =
      "<div class='pl-name'>" + esc(s.label || "Ma playlist") + "</div>" +
      "<div class='pl-url'>" + esc(kind) + (url ? " · " + esc(url) : "") + "</div>";

    if(d.locked){
      $("dStatus").innerHTML = "<span class='badge ok'>Actif</span>";
      badge.className = "badge lock"; badge.textContent = "Conseiller";
      $("lockNote").classList.remove("hide");
      // Lecture seule : pas d'édition/suppression (protège les payants).
    } else {
      $("dStatus").innerHTML = "<span class='badge ok'>Actif</span>";
      badge.className = "badge ok"; badge.textContent = "Ma playlist";
      addAction("Modifier","btn-ghost", function(){ openForm(true, s); });
      addAction("Supprimer","btn-danger", doDelete);
    }
  }

  function addAction(text, cls, fn){
    var b = document.createElement("button");
    b.className = "btn " + cls; b.textContent = text;
    b.addEventListener("click", fn);
    $("plActions").appendChild(b);
  }

  // ---- Formulaire ajout / modif -----------------------------------------
  function openForm(editing, s){
    state.editing = !!editing;
    $("addCard").classList.remove("hide");
    $("addTitle").textContent = editing ? "Modifier ma playlist" : "Ajouter ma playlist";
    $("cancelBtn").classList.toggle("hide", !editing);
    hideMsg($("saveMsg"));
    // Pré-remplissage en modification (jamais le mot de passe : il n'est pas relu).
    $("fName").value = s && s.label ? s.label : "";
    $("fEpg").value  = s && s.epg_url ? s.epg_url : "";
    if(s && s.type === "xtream"){
      setMode("xc");
      $("fHost").value = s.server_url || "";
      $("fUser").value = s.username || "";
      $("fPass").value = "";
    } else {
      setMode("m3u");
      $("fM3u").value = s && s.m3u_url ? s.m3u_url : "";
    }
    $("addCard").scrollIntoView({ behavior:"smooth", block:"center" });
  }
  function hideForm(){ $("addCard").classList.add("hide"); }

  function setMode(m){
    state.mode = m;
    var xc = m === "xc";
    $("tabM3u").classList.toggle("on", !xc);
    $("tabXc").classList.toggle("on", xc);
    $("formM3u").classList.toggle("hide", xc);
    $("formXc").classList.toggle("hide", !xc);
  }

  function save(){
    hideMsg($("saveMsg"));
    var body = { label: ($("fName").value || "").trim() || "Ma playlist" };
    var epg = ($("fEpg").value || "").trim();
    if(epg) body.epg_url = epg;

    if(state.mode === "xc"){
      var host = ($("fHost").value || "").trim();
      var user = ($("fUser").value || "").trim();
      var pass = ($("fPass").value || "").trim();
      if(!/^https?:\\/\\//i.test(host)){ return showMsg($("saveMsg"),"err","Le serveur doit commencer par http:// ou https://"); }
      if(!user || !pass){ return showMsg($("saveMsg"),"err","Renseignez l'utilisateur et le mot de passe."); }
      body.type = "xtream"; body.server_url = host; body.username = user; body.password = pass;
    } else {
      var m3u = ($("fM3u").value || "").trim();
      if(!/^https?:\\/\\//i.test(m3u)){ return showMsg($("saveMsg"),"err","Le lien M3U doit commencer par http:// ou https://"); }
      body.type = "m3u"; body.m3u_url = m3u;
    }

    var btn = $("saveBtn"), old = btn.innerHTML;
    btn.disabled = true; btn.innerHTML = "<span class='spin'></span> Enregistrement…";
    fetch(api(state.mac), {
      method:"POST", headers:{ "Content-Type":"application/json" }, body: JSON.stringify(body)
    })
    .then(function(r){ return r.json().then(function(j){ return { ok:r.ok, j:j }; }); })
    .then(function(res){
      btn.disabled = false; btn.innerHTML = old;
      if(res.ok && res.j && res.j.ok){
        showMsg($("saveMsg"),"ok", res.j.message || "Playlist enregistrée !");
        setTimeout(function(){ hideForm(); load(); }, 900);
      } else {
        showMsg($("saveMsg"),"err", (res.j && res.j.message) || "Enregistrement impossible. Vérifiez vos informations.");
      }
    })
    .catch(function(){
      btn.disabled = false; btn.innerHTML = old;
      showMsg($("saveMsg"),"err","Connexion impossible. Réessayez dans un instant.");
    });
  }

  function doDelete(){
    if(!window.confirm("Supprimer votre playlist de cet appareil ?")) return;
    fetch(api(state.mac), { method:"DELETE", headers:{ "Accept":"application/json" } })
    .then(function(r){ return r.json().catch(function(){ return {}; }); })
    .then(function(j){
      if(j && j.ok){ load(); }
      else { alert((j && j.message) || "Suppression impossible."); }
    })
    .catch(function(){ alert("Connexion impossible. Réessayez."); });
  }

  function logout(){
    try{ localStorage.removeItem("sm_mac"); }catch(e){}
    state.mac = null;
    $("dash").classList.add("hide");
    $("login").classList.remove("hide");
    $("macIn").value = "";
  }

  // ---- Câblage -----------------------------------------------------------
  $("loginBtn").addEventListener("click", doLogin);
  $("macIn").addEventListener("keydown", function(e){ if(e.key === "Enter") doLogin(); });
  $("tabM3u").addEventListener("click", function(){ setMode("m3u"); });
  $("tabXc").addEventListener("click", function(){ setMode("xc"); });
  $("saveBtn").addEventListener("click", save);
  $("cancelBtn").addEventListener("click", function(){ hideForm(); load(); });
  $("refreshBtn").addEventListener("click", load);
  $("logoutBtn").addEventListener("click", logout);

  // Pré-remplissage : #mac=... dans l'URL, sinon dernière MAC utilisée.
  (function boot(){
    var fromHash = "";
    if(location.hash){
      var m = location.hash.match(/mac=([^&]+)/i);
      if(m){ fromHash = normMac(decodeURIComponent(m[1])); }
    }
    var saved = "";
    try{ saved = localStorage.getItem("sm_mac") || ""; }catch(e){}
    var mac = fromHash || saved;
    if(mac && MAC_RX.test(mac)){ state.mac = mac; $("macIn").value = mac; openDash(); }
    else if(mac){ $("macIn").value = mac; }
  })();
})();
</script>
</body>
</html>`;
}
