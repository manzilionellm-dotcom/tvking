/*
 * Master dashboard — a single inert HTML page served by the admin router.
 *
 * Self-contained on purpose (no CDN, no build step, no external fetch): the
 * page ships with the proxy and works on a LAN with no internet. It holds no
 * data of its own; the operator pastes the admin token, and everything shown
 * comes from /admin/overview and the /admin/events stream.
 *
 * Three tabs, matching the three planes: Direct (streams and slots), Cinéma
 * (VOD catalogue) and Appareils (subscriber devices and their subscriptions).
 * Expiry countdowns tick locally against the server clock offset sent with each
 * snapshot, so a timer never drifts away from what the enforcer believes.
 */

export const DASHBOARD_HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TV King — panneau de bord</title>
<style>
  :root { color-scheme: dark; --bg:#121212; --card:#1c1c1f; --line:#2c2c31;
          --fg:rgba(255,255,255,.87); --dim:rgba(255,255,255,.6); --faint:rgba(255,255,255,.38);
          --ok:#7bc47f; --warn:#e0b25c; --bad:#e07a7a; --accent:#6ea8d8; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
         font:14px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif; }
  header { display:flex; gap:12px; align-items:center; padding:16px 24px; border-bottom:1px solid var(--line); }
  h1 { font-size:16px; margin:0; font-weight:600; letter-spacing:.02em; }
  nav { display:flex; gap:8px; padding:12px 24px 0; }
  nav button { background:transparent; border:1px solid transparent; border-bottom:none;
               border-radius:8px 8px 0 0; padding:8px 14px; color:var(--dim); cursor:pointer; }
  nav button.on { background:var(--card); border-color:var(--line); color:var(--fg); }
  main { padding:20px 24px 40px; display:grid; gap:22px; max-width:1240px; }
  section.panel { display:none; }
  section.panel.on { display:grid; gap:22px; }
  input, button, select, textarea { font:inherit; background:var(--card); color:var(--fg);
                  border:1px solid var(--line); border-radius:8px; padding:6px 10px; }
  button { cursor:pointer; }
  button.primary { background:var(--accent); color:#0b1116; border-color:var(--accent); font-weight:600; }
  .tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:12px; }
  .tile { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px 16px; }
  .tile .k { color:var(--faint); font-size:11px; text-transform:uppercase; letter-spacing:.08em; }
  .tile .v { font-size:26px; font-variant-numeric:tabular-nums; margin-top:4px; }
  .block h2 { font-size:12px; text-transform:uppercase; letter-spacing:.08em;
              color:var(--faint); margin:0 0 8px; font-weight:600;
              display:flex; align-items:center; gap:10px; }
  .scroll { overflow-x:auto; }
  table { width:100%; border-collapse:collapse; font-variant-numeric:tabular-nums; }
  th, td { text-align:left; padding:7px 12px; border-bottom:1px solid var(--line); white-space:nowrap; }
  th { color:var(--faint); font-size:11px; text-transform:uppercase; letter-spacing:.06em; font-weight:600; }
  td.actions { display:flex; gap:6px; align-items:center; }
  .pill { padding:1px 8px; border-radius:999px; font-size:12px; border:1px solid var(--line); color:var(--dim); }
  .live, .active { color:var(--ok); border-color:var(--ok); }
  .starved { color:var(--warn); border-color:var(--warn); }
  .idle, .none { color:var(--faint); }
  .expired, .revoked, .disabled, .over { color:var(--bad); border-color:var(--bad); }
  .soon { color:var(--warn); }
  #log { background:var(--card); border:1px solid var(--line); border-radius:12px;
         padding:12px 16px; height:180px; overflow:auto; font-family:ui-monospace,monospace;
         font-size:12px; color:var(--dim); }
  #log div { padding:1px 0; }
  .empty { color:var(--faint); padding:8px 12px; }
  dialog { background:var(--card); color:var(--fg); border:1px solid var(--line);
           border-radius:14px; padding:20px 22px; min-width:380px; }
  dialog::backdrop { background:rgba(0,0,0,.6); }
  dialog h3 { margin:0 0 14px; font-size:15px; }
  .field { display:grid; gap:4px; margin-bottom:10px; }
  .field label { font-size:11px; text-transform:uppercase; letter-spacing:.06em; color:var(--faint); }
  .row { display:flex; gap:10px; }
  .row > * { flex:1; }
  .note { color:var(--faint); font-size:12px; margin:6px 0 0; }
</style>
</head>
<body>
<header>
  <h1>TV King — panneau de bord</h1>
  <span id="state" class="pill">hors ligne</span>
  <span style="flex:1"></span>
  <input id="token" type="password" placeholder="jeton admin" autocomplete="off">
  <button id="connect">Connecter</button>
</header>
<nav>
  <button data-tab="live" class="on">Direct</button>
  <button data-tab="vod">Cinéma / VOD</button>
  <button data-tab="devices">Appareils</button>
</nav>
<main>
  <section class="panel on" data-panel="live">
    <div class="tiles">
      <div class="tile"><div class="k">Connexions montantes</div><div class="v" id="m-up">–</div></div>
      <div class="tile"><div class="k">Maximum atteint</div><div class="v" id="m-max">–</div></div>
      <div class="tile"><div class="k">Clients connectés</div><div class="v" id="m-clients">–</div></div>
      <div class="tile"><div class="k">Requêtes / montée</div><div class="v" id="m-ratio">–</div></div>
      <div class="tile"><div class="k">Octets économisés</div><div class="v" id="m-saved">–</div></div>
    </div>
    <div class="block">
      <h2>Comptes maîtres</h2>
      <div class="scroll"><table>
        <thead><tr><th>Compte</th><th>Signature</th><th>Slots</th><th>Chaînes actives</th>
          <th>Clients</th><th>Bascules</th><th>Refus</th><th>Catalogue</th></tr></thead>
        <tbody id="accounts"></tbody>
      </table></div>
    </div>
    <div class="block">
      <h2>Flux</h2>
      <div class="scroll"><table>
        <thead><tr><th>Chaîne</th><th>État</th><th>Slot</th><th>Clients</th><th>Tampon</th>
          <th>WAN</th><th>LAN</th><th>Bascules</th><th></th></tr></thead>
        <tbody id="streams"></tbody>
      </table></div>
    </div>
    <div class="block">
      <h2>Sessions clientes <span class="pill">aucune donnée personnelle collectée</span></h2>
      <div class="scroll"><table>
        <thead><tr><th>Session</th><th>Appareil</th><th>Compte</th><th>Chaîne</th><th>Reçu</th>
          <th>Perdu</th><th>État</th></tr></thead>
        <tbody id="sessions"></tbody>
      </table></div>
    </div>
    <div class="block">
      <h2>Activité</h2>
      <div id="log"></div>
    </div>
  </section>

  <section class="panel" data-panel="vod">
    <div class="tiles">
      <div class="tile"><div class="k">Films</div><div class="v" id="v-movies">–</div></div>
      <div class="tile"><div class="k">Séries</div><div class="v" id="v-series">–</div></div>
      <div class="tile"><div class="k">Flux catalogués</div><div class="v" id="v-streams">–</div></div>
      <div class="tile"><div class="k">Cache disque</div><div class="v" id="v-cache">–</div></div>
      <div class="tile"><div class="k">Taux de cache</div><div class="v" id="v-hit">–</div></div>
    </div>
    <div class="block">
      <h2>Sources VOD <button id="vod-ingest">Ingérer maintenant</button>
        <button id="vod-add">Ajouter une source</button></h2>
      <div class="scroll"><table>
        <thead><tr><th>Source</th><th>Compte</th><th>Actif</th><th>Dernière ingestion</th>
          <th>Éléments</th><th>Erreur</th><th></th></tr></thead>
        <tbody id="vod-sources"></tbody>
      </table></div>
    </div>
    <div class="block">
      <h2>Catégories <span class="pill">décocher masque la catégorie pour les abonnés</span></h2>
      <div class="scroll"><table>
        <thead><tr><th>Type</th><th>Catégorie</th><th>Titres</th><th>Active</th></tr></thead>
        <tbody id="vod-categories"></tbody>
      </table></div>
    </div>
  </section>

  <section class="panel" data-panel="devices">
    <div class="tiles">
      <div class="tile"><div class="k">Appareils</div><div class="v" id="d-total">–</div></div>
      <div class="tile"><div class="k">Actifs</div><div class="v" id="d-active">–</div></div>
      <div class="tile"><div class="k">Expirés</div><div class="v" id="d-expired">–</div></div>
      <div class="tile"><div class="k">Flux en cours</div><div class="v" id="d-streams">–</div></div>
      <div class="tile"><div class="k">Coupures d'expiration</div><div class="v" id="d-dropped">–</div></div>
    </div>
    <div class="block">
      <h2>Appareils &amp; abonnements
        <button id="dev-add" class="primary">Ajouter un appareil</button></h2>
      <div class="scroll"><table>
        <thead><tr><th>Appareil</th><th>MAC / Login</th><th>Bouquet</th><th>État</th>
          <th>Formule</th><th>Expire dans</th><th>Flux</th><th>Actions</th></tr></thead>
        <tbody id="devices"></tbody>
      </table></div>
      <p class="note">L'authentification par MAC est un identifiant, pas un secret :
        à réserver à un réseau de confiance.</p>
    </div>
    <div class="block">
      <h2>Bouquets</h2>
      <div class="scroll"><table>
        <thead><tr><th>Nom</th><th>Compte maître</th><th>Groupes</th><th>Chaînes</th><th>VOD</th></tr></thead>
        <tbody id="packages"></tbody>
      </table></div>
    </div>
  </section>
</main>

<dialog id="device-dialog">
  <h3 id="device-dialog-title">Ajouter un appareil</h3>
  <div class="field"><label for="f-label">Nom</label><input id="f-label" placeholder="Salon"></div>
  <div class="row">
    <div class="field"><label for="f-mac">Adresse MAC</label><input id="f-mac" placeholder="00:1A:79:AA:BB:CC"></div>
    <div class="field"><label for="f-user">Login Xtream</label><input id="f-user" placeholder="auto"></div>
  </div>
  <div class="row">
    <div class="field"><label for="f-package">Bouquet</label><select id="f-package"></select></div>
    <div class="field"><label for="f-max">Connexions</label><input id="f-max" type="number" min="1" value="1"></div>
  </div>
  <div class="field"><label for="f-plan">Formule</label><select id="f-plan"></select></div>
  <div class="field"><label for="f-note">Note</label><input id="f-note" placeholder=""></div>
  <p class="note" id="f-error"></p>
  <div class="row" style="margin-top:12px">
    <button id="f-cancel">Annuler</button>
    <button id="f-save" class="primary">Enregistrer</button>
  </div>
</dialog>

<script>
(() => {
  const $ = (id) => document.getElementById(id);
  let token = "";
  let snapshot = null;
  let skew = 0; // server clock minus browser clock

  const bytes = (n) => {
    if (!n) return "0";
    const units = ["o", "Ko", "Mo", "Go", "To"];
    const i = Math.min(units.length - 1, Math.floor(Math.log(n) / Math.log(1024)));
    return (n / Math.pow(1024, i)).toFixed(i ? 1 : 0) + " " + units[i];
  };
  const remaining = (ms) => {
    if (ms === null || ms === undefined) return "—";
    if (ms <= 0) return "expiré";
    const m = Math.floor(ms / 60000), d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60);
    if (d > 0) return d + " j " + h + " h";
    if (h > 0) return h + " h " + (m % 60) + " min";
    return m + " min " + Math.floor((ms % 60000) / 1000) + " s";
  };
  const cell = (v) => { const td = document.createElement("td"); td.textContent = String(v ?? "—"); return td; };
  const pill = (text, cls) => {
    const td = document.createElement("td"); const s = document.createElement("span");
    s.className = "pill " + (cls || ""); s.textContent = text; td.appendChild(s); return td;
  };
  const button = (text, onclick, cls) => {
    const b = document.createElement("button"); b.textContent = text; b.onclick = onclick;
    if (cls) b.className = cls; return b;
  };
  const rows = (tbody, items, build, emptyText) => {
    tbody.replaceChildren();
    if (!items || !items.length) {
      const tr = document.createElement("tr"), td = document.createElement("td");
      td.className = "empty"; td.colSpan = 9; td.textContent = emptyText;
      tr.appendChild(td); tbody.appendChild(tr); return;
    }
    for (const item of items) tbody.appendChild(build(item));
  };

  function api(path, init) {
    return fetch("/admin" + path, {
      ...init,
      headers: { "content-type": "application/json", ...(init && init.headers),
                 authorization: "Bearer " + token },
    });
  }
  async function send(path, method, body) {
    const response = await api(path, { method, body: body ? JSON.stringify(body) : undefined });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw new Error(detail.detail || detail.error || ("HTTP " + response.status));
    }
    return response.json();
  }

  // -------------------------------------------------------------- rendering
  const STATES = { live: "en direct", starved: "en bascule", idle: "inactif", stopping: "arrêt" };
  const ACCESS = { active: "actif", expired: "expiré", revoked: "révoqué",
                   none: "sans abonnement", disabled: "désactivé" };

  function renderLive(data) {
    const up = data.upstream;
    $("m-up").textContent = up.active + " / " + up.limit;
    $("m-up").className = "v" + (up.active > up.limit ? " over" : "");
    $("m-max").textContent = up.activeMax;
    $("m-max").className = "v" + (up.activeMax > up.limit ? " over" : "");
    $("m-clients").textContent = data.sessions.length;
    $("m-ratio").textContent = data.efficiency.requestsPerUpstream.toFixed(1) + "×";
    $("m-saved").textContent = bytes(data.efficiency.bytesSaved);

    rows($("accounts"), data.accounts, (a) => {
      const tr = document.createElement("tr");
      tr.append(cell(a.label), cell(a.userAgent),
        cell(a.slots.available + " libre / " + a.slots.capacity),
        cell(a.activeChannels.join(", ") || "—"), cell(a.clients),
        cell(a.slots.swaps), cell(a.slots.denials), cell(a.source + " (" + a.channelCount + ")"));
      return tr;
    }, "aucun compte");

    rows($("streams"), data.streams, (s) => {
      const tr = document.createElement("tr");
      tr.append(cell(s.account + "/" + s.channel), pill(STATES[s.state] || s.state, s.state),
        cell(s.holdsSlot ? "oui" : "non"), cell(s.subscribers), cell(bytes(s.bufferedBytes)),
        cell(bytes(s.bytesFromOrigin)), cell(bytes(s.bytesFannedOut)), cell(s.starves));
      const td = document.createElement("td");
      td.appendChild(button("Arrêter", () =>
        send("/streams/" + encodeURIComponent(s.key) + "/stop", "POST").then(refresh)));
      tr.appendChild(td);
      return tr;
    }, "aucun flux actif");

    rows($("sessions"), data.sessions, (s) => {
      const tr = document.createElement("tr");
      tr.append(cell(s.id), cell(s.deviceLabel || (s.deviceId ? "#" + s.deviceId : "—")),
        cell(s.account), cell(s.channel), cell(bytes(s.bytesDelivered)), cell(bytes(s.droppedBytes)));
      tr.appendChild(pill(s.stalled ? "en bascule" : "en lecture", s.stalled ? "starved" : "live"));
      return tr;
    }, "aucun client connecté");
  }

  function renderVod(vod) {
    if (!vod || !vod.configured) {
      rows($("vod-sources"), [], null, "plan VOD non configuré");
      rows($("vod-categories"), [], null, "plan VOD non configuré");
      return;
    }
    $("v-movies").textContent = vod.counts.movies;
    $("v-series").textContent = vod.counts.series;
    $("v-streams").textContent = vod.counts.streams;
    $("v-cache").textContent = bytes(vod.cache.bytes);
    $("v-hit").textContent = Math.round(vod.cache.hitRatio * 100) + " %";

    rows($("vod-sources"), vod.sources, (s) => {
      const tr = document.createElement("tr");
      const toggle = document.createElement("input");
      toggle.type = "checkbox"; toggle.checked = s.enabled;
      toggle.onchange = () => send("/vod/sources/" + s.id, "PATCH", { enabled: toggle.checked }).then(refresh);
      const active = document.createElement("td"); active.appendChild(toggle);
      tr.append(cell(s.name), cell(s.accountId));
      tr.appendChild(active);
      tr.append(cell(s.lastIngestAt ? new Date(s.lastIngestAt).toLocaleString() : "jamais"),
        cell(s.lastItems), cell(s.lastError || "—"));
      const td = document.createElement("td");
      td.appendChild(button("Ingérer", () => send("/vod/ingest", "POST", { sourceId: s.id }).then(refresh)));
      td.appendChild(button("Supprimer", () => send("/vod/sources/" + s.id, "DELETE").then(refresh)));
      td.className = "actions";
      tr.appendChild(td);
      return tr;
    }, "aucune source VOD");

    rows($("vod-categories"), vod.categories, (c) => {
      const tr = document.createElement("tr");
      const toggle = document.createElement("input");
      toggle.type = "checkbox"; toggle.checked = c.enabled;
      toggle.onchange = () => send("/vod/categories/" + c.id, "PATCH", { enabled: toggle.checked }).then(refresh);
      const td = document.createElement("td"); td.appendChild(toggle);
      tr.append(cell(c.kind === "movie" ? "Film" : "Série"), cell(c.name), cell(c.titles));
      tr.appendChild(td);
      return tr;
    }, "aucune catégorie");
  }

  function renderDevices(portal) {
    if (!portal || !portal.configured) {
      rows($("devices"), [], null, "plan abonnés non configuré");
      rows($("packages"), [], null, "plan abonnés non configuré");
      return;
    }
    const devices = portal.devices;
    const planLabels = new Map(portal.plans.map((plan) => [plan.id, plan.label]));
    $("d-total").textContent = devices.length;
    $("d-active").textContent = devices.filter((d) => d.state === "active").length;
    $("d-expired").textContent = devices.filter((d) => d.state === "expired" || d.state === "revoked").length;
    $("d-streams").textContent = devices.reduce((n, d) => n + d.activeSessions, 0);
    $("d-dropped").textContent = portal.enforcer ? portal.enforcer.droppedSessions : "—";

    rows($("devices"), devices, (d) => {
      const tr = document.createElement("tr");
      tr.append(cell(d.label || "—"), cell(d.mac || d.username || "—"), cell(d.packageName || "—"));
      tr.appendChild(pill(ACCESS[d.state] || d.state, d.state));
      tr.append(cell(d.plan ? planLabels.get(d.plan) || d.plan : "—"));

      const timer = document.createElement("td");
      timer.dataset.expiresAt = d.expiresAt === null ? "" : String(d.expiresAt);
      timer.className = "timer";
      // No grant at all is not "expired": say nothing rather than something wrong.
      timer.textContent = d.expiresAt === null ? "—" : remaining(d.remainingMs);
      tr.appendChild(timer);
      tr.append(cell(d.activeSessions + " / " + d.maxConnections));

      const actions = document.createElement("td");
      actions.className = "actions";
      const plans = document.createElement("select");
      for (const plan of portal.plans) {
        const option = document.createElement("option");
        option.value = plan.id; option.textContent = plan.label;
        plans.appendChild(option);
      }
      actions.appendChild(plans);
      actions.appendChild(button("Appliquer", () =>
        send("/devices/" + d.id + "/grant", "POST", { plan: plans.value }).then(refresh)));
      actions.appendChild(button("Essai 24 h", () =>
        send("/devices/" + d.id + "/grant", "POST", { plan: "trial-24h" }).then(refresh)));
      actions.appendChild(button("Révoquer", () =>
        send("/devices/" + d.id + "/revoke", "POST").then(refresh)));
      actions.appendChild(button("Supprimer", () =>
        send("/devices/" + d.id, "DELETE").then(refresh)));
      tr.appendChild(actions);
      return tr;
    }, "aucun appareil");

    rows($("packages"), portal.packages, (p) => {
      const tr = document.createElement("tr");
      tr.append(cell(p.name), cell(p.accountId), cell(p.groups.join(", ") || "tous"),
        cell(p.channels.length || "toutes"), cell(p.vodEnabled ? "oui" : "non"));
      return tr;
    }, "aucun bouquet");
  }

  function render(data) {
    snapshot = data;
    // Countdowns tick against the SERVER clock: a browser an hour off must not
    // show an expiry the enforcer disagrees with.
    const serverNow = data.portal && data.portal.devices && data.portal.devices[0]
      ? data.portal.devices[0].now : Date.now();
    skew = serverNow - Date.now();
    renderLive(data);
    renderVod(data.vod);
    renderDevices(data.portal);
  }

  function tickTimers() {
    if (!snapshot) return;
    const now = Date.now() + skew;
    for (const td of document.querySelectorAll("td.timer")) {
      const expiresAt = td.dataset.expiresAt;
      if (!expiresAt) continue;
      const left = Number(expiresAt) - now;
      td.textContent = remaining(left);
      td.className = "timer" + (left <= 0 ? " expired" : left < 3600000 ? " soon" : "");
    }
  }
  setInterval(tickTimers, 1000);

  async function refresh() {
    try { render(await send("/overview", "GET")); } catch (error) { log({ type: "error", message: String(error) }); }
  }

  function log(event) {
    const line = document.createElement("div");
    const rest = Object.entries(event).filter(([k]) => k !== "type")
      .map(([k, v]) => k + "=" + v).join(" ");
    line.textContent = new Date().toLocaleTimeString() + "  " + event.type + "  " + rest;
    const box = $("log");
    box.appendChild(line);
    while (box.childElementCount > 200) box.removeChild(box.firstChild);
    box.scrollTop = box.scrollHeight;
  }

  // ------------------------------------------------------------------ modal
  const dialog = $("device-dialog");
  $("dev-add").onclick = () => {
    $("f-error").textContent = "";
    const packages = (snapshot && snapshot.portal && snapshot.portal.packages) || [];
    $("f-package").replaceChildren();
    for (const pack of packages) {
      const option = document.createElement("option");
      option.value = String(pack.id); option.textContent = pack.name + " (" + pack.accountId + ")";
      $("f-package").appendChild(option);
    }
    $("f-plan").replaceChildren();
    for (const plan of (snapshot && snapshot.portal && snapshot.portal.plans) || []) {
      const option = document.createElement("option");
      option.value = plan.id; option.textContent = plan.label;
      $("f-plan").appendChild(option);
    }
    dialog.showModal();
  };
  $("f-cancel").onclick = () => dialog.close();
  $("f-save").onclick = async () => {
    try {
      const body = {
        label: $("f-label").value.trim(),
        mac: $("f-mac").value.trim() || null,
        username: $("f-user").value.trim() || null,
        packageId: $("f-package").value ? Number($("f-package").value) : null,
        maxConnections: Number($("f-max").value) || 1,
        plan: $("f-plan").value,
        note: $("f-note").value.trim(),
      };
      const result = await send("/devices", "POST", body);
      if (result.credentials) {
        log({ type: "credentials", user: result.credentials.username, password: result.credentials.password });
      }
      dialog.close();
      await refresh();
    } catch (error) {
      $("f-error").textContent = String(error);
    }
  };

  $("vod-ingest").onclick = () => send("/vod/ingest", "POST", {}).then(refresh);
  $("vod-add").onclick = async () => {
    const name = prompt("Nom de la source VOD ?");
    if (!name) return;
    const url = prompt("URL de la playlist M3U ?");
    if (!url) return;
    const accountId = prompt("Compte maître ?", (snapshot && snapshot.accounts[0] && snapshot.accounts[0].id) || "master");
    if (!accountId) return;
    try { await send("/vod/sources", "POST", { name, url, accountId }); await refresh(); }
    catch (error) { log({ type: "error", message: String(error) }); }
  };

  for (const tab of document.querySelectorAll("nav button")) {
    tab.onclick = () => {
      for (const other of document.querySelectorAll("nav button")) other.classList.toggle("on", other === tab);
      for (const panel of document.querySelectorAll("section.panel")) {
        panel.classList.toggle("on", panel.dataset.panel === tab.dataset.tab);
      }
    };
  }

  // ----------------------------------------------------------------- stream
  function connect() {
    token = $("token").value.trim();
    if (!token) return;
    // EventSource cannot send headers, so the live stream is read through
    // fetch + a reader over the same authenticated endpoint.
    api("/events").then(async (response) => {
      if (!response.ok) { $("state").textContent = "refusé"; return; }
      $("state").textContent = "en ligne"; $("state").className = "pill live";
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let split;
        while ((split = buffer.indexOf("\\n\\n")) >= 0) {
          const frame = buffer.slice(0, split);
          buffer = buffer.slice(split + 2);
          const kind = /event: (\\w+)/.exec(frame);
          const payload = /data: (.*)/.exec(frame);
          if (!kind || !payload) continue;
          const data = JSON.parse(payload[1]);
          if (kind[1] === "overview") render(data); else log(data);
        }
      }
      $("state").textContent = "hors ligne"; $("state").className = "pill";
    }).catch(() => { $("state").textContent = "hors ligne"; $("state").className = "pill"; });
  }

  $("connect").onclick = connect;
  $("token").addEventListener("keydown", (e) => { if (e.key === "Enter") connect(); });
})();
</script>
</body>
</html>`;
