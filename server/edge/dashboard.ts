/*
 * Master dashboard — a single inert HTML page served by the admin router.
 *
 * Self-contained on purpose (no CDN, no build step, no external fetch): the
 * page ships with the proxy and works on a LAN with no internet. It holds no
 * data of its own; the operator pastes the admin token, and everything shown
 * comes from /admin/overview and the /admin/events stream.
 */

export const DASHBOARD_HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TV King — proxy de bord</title>
<style>
  :root { color-scheme: dark; --bg:#121212; --card:#1c1c1f; --line:#2c2c31;
          --fg:rgba(255,255,255,.87); --dim:rgba(255,255,255,.6); --faint:rgba(255,255,255,.38);
          --ok:#7bc47f; --warn:#e0b25c; --bad:#e07a7a; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
         font:14px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif; }
  header { display:flex; gap:12px; align-items:center; padding:16px 24px; border-bottom:1px solid var(--line); }
  h1 { font-size:16px; margin:0; font-weight:600; letter-spacing:.02em; }
  main { padding:24px; display:grid; gap:24px; max-width:1200px; }
  input, button { font:inherit; background:var(--card); color:var(--fg);
                  border:1px solid var(--line); border-radius:8px; padding:6px 10px; }
  button { cursor:pointer; }
  .tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:12px; }
  .tile { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px 16px; }
  .tile .k { color:var(--faint); font-size:11px; text-transform:uppercase; letter-spacing:.08em; }
  .tile .v { font-size:26px; font-variant-numeric:tabular-nums; margin-top:4px; }
  section h2 { font-size:12px; text-transform:uppercase; letter-spacing:.08em;
               color:var(--faint); margin:0 0 8px; font-weight:600; }
  .scroll { overflow-x:auto; }
  table { width:100%; border-collapse:collapse; font-variant-numeric:tabular-nums; }
  th, td { text-align:left; padding:7px 12px; border-bottom:1px solid var(--line); white-space:nowrap; }
  th { color:var(--faint); font-size:11px; text-transform:uppercase; letter-spacing:.06em; font-weight:600; }
  .pill { padding:1px 8px; border-radius:999px; font-size:12px; border:1px solid var(--line); color:var(--dim); }
  .live { color:var(--ok); border-color:var(--ok); }
  .starved { color:var(--warn); border-color:var(--warn); }
  .idle { color:var(--faint); }
  .over { color:var(--bad); }
  #log { background:var(--card); border:1px solid var(--line); border-radius:12px;
         padding:12px 16px; height:190px; overflow:auto; font-family:ui-monospace,monospace;
         font-size:12px; color:var(--dim); }
  #log div { padding:1px 0; }
  .empty { color:var(--faint); padding:8px 12px; }
</style>
</head>
<body>
<header>
  <h1>TV King — proxy de bord</h1>
  <span id="state" class="pill">hors ligne</span>
  <span style="flex:1"></span>
  <input id="token" type="password" placeholder="jeton admin" autocomplete="off">
  <button id="connect">Connecter</button>
</header>
<main>
  <div class="tiles">
    <div class="tile"><div class="k">Connexions montantes</div><div class="v" id="m-up">–</div></div>
    <div class="tile"><div class="k">Maximum atteint</div><div class="v" id="m-max">–</div></div>
    <div class="tile"><div class="k">Clients connectés</div><div class="v" id="m-clients">–</div></div>
    <div class="tile"><div class="k">Requêtes / montée</div><div class="v" id="m-ratio">–</div></div>
    <div class="tile"><div class="k">Octets économisés</div><div class="v" id="m-saved">–</div></div>
  </div>
  <section>
    <h2>Comptes maîtres</h2>
    <div class="scroll"><table>
      <thead><tr><th>Compte</th><th>Signature</th><th>Slots</th><th>Chaînes actives</th>
        <th>Clients</th><th>Bascules</th><th>Refus</th><th>Catalogue</th></tr></thead>
      <tbody id="accounts"></tbody>
    </table></div>
  </section>
  <section>
    <h2>Flux</h2>
    <div class="scroll"><table>
      <thead><tr><th>Chaîne</th><th>État</th><th>Slot</th><th>Clients</th><th>Tampon</th>
        <th>WAN</th><th>LAN</th><th>Bascules</th><th></th></tr></thead>
      <tbody id="streams"></tbody>
    </table></div>
  </section>
  <section>
    <h2>Sessions clientes <span class="pill">identifiants opaques — aucune donnée personnelle</span></h2>
    <div class="scroll"><table>
      <thead><tr><th>Session</th><th>Compte</th><th>Chaîne</th><th>Reçu</th>
        <th>Perdu</th><th>File</th><th>État</th></tr></thead>
      <tbody id="sessions"></tbody>
    </table></div>
  </section>
  <section>
    <h2>Activité</h2>
    <div id="log"></div>
  </section>
</main>
<script>
(() => {
  const $ = (id) => document.getElementById(id);
  let token = "";
  let source = null;

  const bytes = (n) => {
    if (!n) return "0";
    const units = ["o", "Ko", "Mo", "Go", "To"];
    const i = Math.min(units.length - 1, Math.floor(Math.log(n) / Math.log(1024)));
    return (n / Math.pow(1024, i)).toFixed(i ? 1 : 0) + " " + units[i];
  };
  const cell = (value) => { const td = document.createElement("td"); td.textContent = String(value); return td; };
  const pill = (text, cls) => {
    const td = document.createElement("td");
    const span = document.createElement("span");
    span.className = "pill " + (cls || "");
    span.textContent = text;
    td.appendChild(span);
    return td;
  };
  const STATES = { live: "en direct", starved: "en bascule", idle: "inactif", stopping: "arrêt" };
  const rows = (tbody, items, build, emptyText) => {
    tbody.replaceChildren();
    if (!items.length) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.className = "empty";
      td.colSpan = 9;
      td.textContent = emptyText;
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    for (const item of items) tbody.appendChild(build(item));
  };

  function render(data) {
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
      tr.append(
        cell(a.label),
        cell(a.userAgent),
        cell(a.slots.available + " libre / " + a.slots.capacity),
        cell(a.activeChannels.join(", ") || "—"),
        cell(a.clients),
        cell(a.slots.swaps),
        cell(a.slots.denials),
        cell(a.source + " (" + a.channelCount + ")")
      );
      return tr;
    }, "aucun compte");

    rows($("streams"), data.streams, (s) => {
      const tr = document.createElement("tr");
      tr.append(
        cell(s.account + "/" + s.channel),
        pill(STATES[s.state] || s.state, s.state),
        cell(s.holdsSlot ? "oui" : "non"),
        cell(s.subscribers),
        cell(bytes(s.bufferedBytes)),
        cell(bytes(s.bytesFromOrigin)),
        cell(bytes(s.bytesFannedOut)),
        cell(s.starves)
      );
      const td = document.createElement("td");
      const button = document.createElement("button");
      button.textContent = "Arrêter";
      button.onclick = () => api("/streams/" + encodeURIComponent(s.key) + "/stop", { method: "POST" });
      td.appendChild(button);
      tr.appendChild(td);
      return tr;
    }, "aucun flux actif");

    rows($("sessions"), data.sessions, (s) => {
      const tr = document.createElement("tr");
      tr.append(
        cell(s.id),
        cell(s.account),
        cell(s.channel),
        cell(bytes(s.bytesDelivered)),
        cell(bytes(s.droppedBytes)),
        cell(bytes(s.queuedBytes))
      );
      tr.appendChild(pill(s.stalled ? "en bascule" : "en lecture", s.stalled ? "starved" : "live"));
      return tr;
    }, "aucun client connecté");
  }

  function log(event) {
    const line = document.createElement("div");
    const time = new Date().toLocaleTimeString();
    const rest = Object.entries(event)
      .filter(([k]) => k !== "type")
      .map(([k, v]) => k + "=" + v)
      .join(" ");
    line.textContent = time + "  " + event.type + "  " + rest;
    const box = $("log");
    box.appendChild(line);
    while (box.childElementCount > 200) box.removeChild(box.firstChild);
    box.scrollTop = box.scrollHeight;
  }

  function api(path, init) {
    return fetch("/admin" + path, {
      ...init,
      headers: { ...(init && init.headers), authorization: "Bearer " + token },
    });
  }

  function connect() {
    token = $("token").value.trim();
    if (!token) return;
    if (source) source.close();

    // EventSource cannot send headers, so the live stream is opened through
    // fetch + a reader over the same authenticated endpoint.
    api("/events").then(async (response) => {
      if (!response.ok) { $("state").textContent = "refusé"; return; }
      $("state").textContent = "en ligne";
      $("state").className = "pill live";
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
      $("state").textContent = "hors ligne";
      $("state").className = "pill";
    }).catch(() => { $("state").textContent = "hors ligne"; $("state").className = "pill"; });
  }

  $("connect").onclick = connect;
  $("token").addEventListener("keydown", (e) => { if (e.key === "Enter") connect(); });
})();
</script>
</body>
</html>`;
