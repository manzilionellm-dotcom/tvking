// =========================================================
//  portal.js — « Mon espace » : gérer SES playlists (façon IBO Player Pro)
// =========================================================
//  Page cliente servie sur /mon-espace par worker.js (import portalHtml).
//  Le client entre SA MAC → il voit TOUTES ses playlists et peut en AJOUTER
//  autant qu'il veut (M3U ou Xtream), les MODIFIER, les SUPPRIMER. Une playlist
//  posée par le PANEL (client payant) reste VERROUILLÉE (lecture seule) mais
//  n'empêche JAMAIS d'en ajouter d'autres à côté (« ça avale toujours »).
//
//  Back-end : /api/self-source/:mac  (GET | POST | DELETE?id=) dans worker.js.
//  Le mot de passe Xtream n'est JAMAIS relu. Même origine → pas de CORS.
//  noindex (outil client, pas du référencement).
//
//  IMPORTANT : module JS importé tel quel (pas ré-échappé comme landing.js). Le
//  JS de la PAGE évite volontairement les backticks / ${} (concaténation par +)
//  pour ne pas casser le template literal extérieur.
// =========================================================

export function portalHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Mon espace — Gérer mes playlists | 7 MOTION</title>
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
  main{padding:40px 0 90px}
  .eyebrow{display:inline-block;color:var(--gold);font-size:12px;font-weight:700;
    letter-spacing:3px;text-transform:uppercase;margin-bottom:14px}
  h1{font-family:var(--serif);font-weight:600;font-size:clamp(28px,6vw,40px);
    line-height:1.1;letter-spacing:-.4px}
  h2{font-family:var(--serif);font-weight:600;font-size:22px;letter-spacing:-.3px}
  .lead{color:var(--muted);font-size:16px;margin-top:12px}
  .card{background:linear-gradient(180deg,var(--panel-2),var(--panel));
    border:1px solid var(--line);border-radius:var(--radius);padding:24px;margin-top:20px}
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
  .btn-sm{width:auto;padding:9px 16px;font-size:13.5px}
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
  .badge{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;font-weight:800;
    letter-spacing:.5px;padding:5px 11px;border-radius:999px;text-transform:uppercase;white-space:nowrap}
  .badge.ok{background:rgba(62,207,142,.14);color:var(--green);border:1px solid rgba(62,207,142,.3)}
  .badge.lock{background:rgba(216,183,102,.14);color:var(--gold-bright);border:1px solid var(--line-gold)}
  .badge.wait{background:rgba(255,255,255,.06);color:var(--muted);border:1px solid var(--line)}
  /* Liste des playlists */
  .pl{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;
    background:rgba(0,0,0,.22);border:1px solid var(--line);border-radius:15px;
    padding:16px 17px;margin-top:12px}
  .pl.locked{border-color:var(--line-gold)}
  .pl-main{min-width:0;flex:1}
  .pl-name{font-weight:800;font-size:16px;display:flex;align-items:center;gap:9px;flex-wrap:wrap}
  .pl-url{color:var(--muted);font-size:13px;margin-top:5px;word-break:break-all}
  .pl-act{display:flex;flex-direction:column;gap:8px;flex-shrink:0}
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
    <h1>Gérez vos playlists</h1>
    <p class="lead">Entrez l'adresse de votre appareil (elle s'affiche sur l'écran d'accueil de l'app, ou dans « À&nbsp;propos&nbsp;»). Ajoutez autant de playlists que vous voulez — M3U ou Xtream — et elles arrivent toutes seules sur l'appareil.</p>
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

    <!-- Liste des playlists -->
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:12px">
        <h2>Mes playlists</h2>
        <span id="plCount" class="badge wait">—</span>
      </div>
      <div id="plList" style="margin-top:6px"></div>
      <div style="margin-top:18px"></div>
      <button class="btn btn-gold" id="addBtn">＋ Ajouter une playlist</button>
      <p class="hint" id="addHint">Ajoutez-en autant que vous voulez. Elles apparaissent toutes dans l'app.</p>
    </div>

    <!-- Ajouter / modifier -->
    <div class="card gold hide" id="addCard">
      <h2 id="addTitle">Ajouter une playlist</h2>
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
      <button class="btn btn-gold" id="saveBtn">Enregistrer</button>
      <button class="btn btn-ghost" id="cancelBtn" style="margin-top:10px">Annuler</button>
      <div id="saveMsg" class="msg"></div>
      <p class="hint">Après enregistrement, ouvrez (ou redémarrez) l'app : vos chaînes apparaissent automatiquement.</p>
    </div>

    <div class="btn-row" style="margin-top:24px">
      <button class="btn btn-ghost" id="refreshBtn">Rafraîchir</button>
      <button class="btn btn-ghost" id="logoutBtn">Changer d'appareil</button>
    </div>

    <p class="foot">7&nbsp;MOTION est un lecteur multimédia. Vous fournissez vos propres playlists ;
      aucun contenu n'est fourni par le service. Besoin d'aide ? Un conseiller reste disponible.</p>
  </section>

</div></main>

<script>
(function(){
  "use strict";
  var MAC_RX = /^MK(:[0-9A-F]{2}){5}$/;
  // MAC en clair dans le path (les « : » sont valides en URL) ; le worker valide
  // la forme brute — l'encoder en %3A la ferait rejeter.
  var api = function(mac){ return "/api/self-source/" + mac; };
  var $ = function(id){ return document.getElementById(id); };
  var state = { mac:null, mode:"m3u", editId:null, canAdd:true };

  function normMac(v){ return String(v||"").toUpperCase().replace(/\\s+/g,"").replace(/-/g,":"); }
  function showMsg(el, kind, text){ el.className = "msg " + kind + " show"; el.textContent = text; }
  function hideMsg(el){ el.className = "msg"; el.textContent = ""; }
  function esc(s){ return String(s==null?"":s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }

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

  // ---- Charger la liste des playlists ------------------------------------
  function load(){
    $("dStatus").textContent = "Chargement…";
    $("plCount").className = "badge wait"; $("plCount").textContent = "…";
    $("plList").innerHTML = "<p class='hint'>Chargement…</p>";
    fetch(api(state.mac), { headers:{ "Accept":"application/json" } })
      .then(function(r){ return r.json().catch(function(){ return {}; }); })
      .then(render)
      .catch(function(){
        $("dStatus").innerHTML = "<span class='badge wait'>Hors ligne</span>";
        $("plList").innerHTML = "<p class='hint'>Connexion impossible. Touchez « Rafraîchir ».</p>";
      });
  }

  function render(d){
    if(!d || d.ok !== true){
      $("dStatus").textContent = "—";
      $("plCount").className = "badge wait"; $("plCount").textContent = "—";
      $("plList").innerHTML = "<p class='hint'>Impossible de lire vos playlists pour le moment. Touchez « Rafraîchir ».</p>";
      return;
    }
    var items = d.items || [];
    state.canAdd = d.canAdd !== false;
    $("dStatus").innerHTML = "<span class='badge ok'>Actif</span>";
    $("plCount").className = items.length ? "badge ok" : "badge wait";
    $("plCount").textContent = items.length ? (items.length + (items.length>1?" listes":" liste")) : "Aucune";

    if(!items.length){
      $("plList").innerHTML = "<p class='hint'>Aucune playlist pour l'instant. Touchez « ＋ Ajouter une playlist » ci-dessous.</p>";
    } else {
      $("plList").innerHTML = "";
      items.forEach(function(it){ $("plList").appendChild(itemRow(it)); });
    }

    // Bouton « Ajouter » : toujours visible ; désactivé seulement si plafond atteint.
    $("addBtn").disabled = !state.canAdd;
    $("addHint").textContent = state.canAdd
      ? "Ajoutez-en autant que vous voulez. Elles apparaissent toutes dans l'app."
      : "Limite atteinte (" + (d.maxItems||20) + "). Supprimez-en une pour en ajouter une autre.";
  }

  function itemRow(it){
    var wrap = document.createElement("div");
    wrap.className = "pl" + (it.locked ? " locked" : "");
    var kind = it.type === "xtream" ? "Xtream (XC)" : "Lien M3U";
    var url = it.type === "xtream" ? (it.server_url || "") : (it.m3u_url || "");
    var badge = it.locked
      ? "<span class='badge lock'>Conseiller</span>"
      : "<span class='badge ok'>Ma liste</span>";

    var main = document.createElement("div");
    main.className = "pl-main";
    main.innerHTML =
      "<div class='pl-name'>" + esc(it.label || "Ma playlist") + " " + badge + "</div>" +
      "<div class='pl-url'>" + esc(kind) + (url ? " · " + esc(url) : "") + "</div>";
    wrap.appendChild(main);

    var act = document.createElement("div");
    act.className = "pl-act";
    if(it.locked){
      var lk = document.createElement("span");
      lk.className = "hint"; lk.style.fontSize = "12px"; lk.style.margin = "0";
      lk.textContent = "Protégée";
      act.appendChild(lk);
    } else {
      var edit = document.createElement("button");
      edit.className = "btn btn-ghost btn-sm"; edit.textContent = "Modifier";
      edit.addEventListener("click", function(){ openForm(it); });
      var del = document.createElement("button");
      del.className = "btn btn-danger btn-sm"; del.textContent = "Supprimer";
      del.addEventListener("click", function(){ doDelete(it); });
      act.appendChild(edit); act.appendChild(del);
    }
    wrap.appendChild(act);
    return wrap;
  }

  // ---- Formulaire ajout / modif -----------------------------------------
  function openForm(item){
    state.editId = item && item.id ? item.id : null;
    $("addCard").classList.remove("hide");
    $("addTitle").textContent = state.editId ? "Modifier la playlist" : "Ajouter une playlist";
    $("saveBtn").textContent = state.editId ? "Enregistrer les changements" : "Ajouter";
    hideMsg($("saveMsg"));
    $("fName").value = item && item.label ? item.label : "";
    $("fEpg").value  = item && item.epg_url ? item.epg_url : "";
    if(item && item.type === "xtream"){
      setMode("xc");
      $("fHost").value = item.server_url || "";
      $("fUser").value = item.username || "";
      $("fPass").value = ""; // le mot de passe n'est jamais relu → à re-saisir
    } else {
      setMode("m3u");
      $("fM3u").value = item && item.m3u_url ? item.m3u_url : "";
    }
    $("addCard").scrollIntoView({ behavior:"smooth", block:"center" });
  }
  function hideForm(){ $("addCard").classList.add("hide"); state.editId = null; }

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
    if(state.editId) body.id = state.editId;
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
    .then(function(r){ return r.json().then(function(j){ return { ok:r.ok, j:j }; }).catch(function(){ return { ok:false, j:{} }; }); })
    .then(function(res){
      btn.disabled = false; btn.innerHTML = old;
      if(res.ok && res.j && res.j.ok){
        showMsg($("saveMsg"),"ok", res.j.message || "Playlist enregistrée !");
        setTimeout(function(){ hideForm(); load(); }, 800);
      } else {
        showMsg($("saveMsg"),"err", (res.j && res.j.message) || "Enregistrement impossible. Vérifiez vos informations.");
      }
    })
    .catch(function(){
      btn.disabled = false; btn.innerHTML = old;
      showMsg($("saveMsg"),"err","Connexion impossible. Réessayez dans un instant.");
    });
  }

  function doDelete(item){
    if(!item || !item.id) return;
    if(!window.confirm("Supprimer « " + (item.label || "cette playlist") + " » ?")) return;
    fetch(api(state.mac) + "?id=" + encodeURIComponent(item.id), {
      method:"DELETE", headers:{ "Accept":"application/json" }
    })
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
  $("addBtn").addEventListener("click", function(){ if(state.canAdd) openForm(null); });
  $("saveBtn").addEventListener("click", save);
  $("cancelBtn").addEventListener("click", function(){ hideForm(); });
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
