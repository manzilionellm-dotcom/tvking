// load_500.mjs — PREUVE PAR TEST DE CHARGE.
//
// Objectif : démontrer, chiffres à l'appui, que le gateway sert 500+ spectateurs
// sur LA MÊME chaîne avec UNE SEULE connexion fournisseur (mutualisation hub.js).
//
// Le test monte tout en local, sans réseau externe :
//   1) un FAUX upstream qui émet un flux TS/octets continu et COMPTE ses connexions ;
//   2) le vrai gateway (createServer) pointé sur ce faux upstream ;
//   3) 500 clients HTTP simultanés sur la MÊME chaîne (streamId identique).
//
// Invariants vérifiés (sortie en erreur = exit(1) si l'un casse) :
//   A. 1 SEULE connexion upstream ouverte (pas 500).
//   B. Les 500 clients reçoivent bien des octets.
//   C. La mémoire tampon reste bornée (< plafond global).
//   D. Un client lent NE bloque PAS les autres (il est coupé par le backpressure,
//      les clients sains continuent de recevoir le live).
//
// Bonus vérifié : au-delà de PROVIDER_MAX_CONNECTIONS chaînes DISTINCTES → 503 propre.
//
// Lancement : node gateway/test/load_500.mjs

import http from 'node:http';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { createServer } = require('../src/server.js');

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---- Paramètres du test (surchargables par variables d'env) -----------------
const N_CLIENTS = Number(process.env.LOAD_CLIENTS || 500);
const N_SLOW = Number(process.env.LOAD_SLOW || 5); // clients volontairement lents
// Durée de mesure : 12 s. Sur loopback, les buffers noyau (recv + send, avec
// autotuning) absorbent plusieurs Mo avant que la file userspace d'un client
// pausé ne grossisse ; il faut ~7 s pour franchir le cap de 1 Mo. 12 s laisse
// donc au balayage de backpressure le temps de couper les clients lents.
const RUN_MS = Number(process.env.LOAD_RUN_MS || 12000);
// 16 Ko toutes les 20 ms ≈ 0,8 Mo/s par flux. Débit modéré que la boucle
// d'événements tient sans peine à 500 sockets sur loopback (sinon l'établissement
// des connexions serait affamé). Pour rendre la coupe des clients lents
// DÉTERMINISTE à ce débit, on abaisse le cap par client dans la config du test
// (TEST_CLIENT_CAP ci-dessous) : un client pausé l'atteint en ~1,3 s.
const CHUNK_BYTES = Number(process.env.LOAD_CHUNK || 16 * 1024); // 16 Ko / tick
const TICK_MS = Number(process.env.LOAD_TICK_MS || 20);
// Cap par client utilisé UNIQUEMENT pour ce test (le défaut de prod reste 8 Mo).
const TEST_CLIENT_CAP = Number(process.env.LOAD_CLIENT_CAP || 1024 * 1024); // 1 Mo

// Codes couleur ANSI simples pour un rapport lisible.
const c = {
  g: (s) => `\x1b[32m${s}\x1b[0m`,
  r: (s) => `\x1b[31m${s}\x1b[0m`,
  y: (s) => `\x1b[33m${s}\x1b[0m`,
  b: (s) => `\x1b[1m${s}\x1b[0m`,
};

function mb(bytes) {
  return (bytes / 1024 / 1024).toFixed(1);
}

// ============================================================================
// 1) FAUX UPSTREAM — émet un flux d'octets continu et compte ses connexions.
// ============================================================================
let upstreamConnections = 0; // total de connexions reçues (cumulé)
let upstreamActive = 0; // connexions actuellement ouvertes
const upstreamTimers = new Set();

const fakeUpstream = http.createServer((req, res) => {
  upstreamConnections += 1;
  upstreamActive += 1;
  res.writeHead(200, { 'Content-Type': 'video/MP2T', Connection: 'keep-alive' });

  // Émet un « paquet TS » factice toutes les TICK_MS, indéfiniment.
  const buf = Buffer.alloc(CHUNK_BYTES, 0x47); // 0x47 = octet de sync TS
  const timer = setInterval(() => {
    // On ignore la valeur de retour : c'est le gateway qui gère le backpressure
    // en aval, pas nous. Ici on simule une source « qui pousse » en continu.
    res.write(buf);
  }, TICK_MS);
  upstreamTimers.add(timer);

  const stop = () => {
    clearInterval(timer);
    upstreamTimers.delete(timer);
    upstreamActive -= 1;
  };
  res.on('close', stop);
  req.on('close', stop);
});

// ============================================================================
// Utilitaires de démarrage
// ============================================================================
function listen(server, port = 0, host = '127.0.0.1') {
  return new Promise((resolve) => server.listen(port, host, () => resolve(server.address().port)));
}

async function main() {
  console.log(c.b('\n═══ TEST DE CHARGE — 500 spectateurs / 1 upstream ═══\n'));

  // ---- Démarrage du faux upstream ------------------------------------------
  const upstreamPort = await listen(fakeUpstream);
  console.log(`Faux upstream sur http://127.0.0.1:${upstreamPort}`);

  // ---- Configuration du gateway (sans .env : on injecte l'objet) -----------
  const cfg = {
    PORT: 0,
    HOST: '127.0.0.1',
    PUBLIC_BASE: '',
    UPSTREAM_BASE: `http://127.0.0.1:${upstreamPort}`,
    UPSTREAM_USER: 'up',
    UPSTREAM_PASS: 'up',
    PROVIDER_MAX_CONNECTIONS: 1, // ← LA contrainte dure (ligne à 1 connexion)
    BROADCAST_USER: 'diff',
    BROADCAST_PASS: 'diff',
    BROADCAST_MAX_STREAMS: Math.max(N_CLIENTS + 10, 500),
    CLIENT_BUFFER_MAX_BYTES: TEST_CLIENT_CAP, // 1 Mo pour ce test (prod : 8 Mo)
    GLOBAL_CLIENT_BUFFER_MAX_BYTES: 512 * 1024 * 1024,
    SWEEP_INTERVAL_MS: 500,
    UPSTREAM_TIMEOUT_MS: 30000,
    KEEPALIVE_MS: 15000,
    UPSTREAM_MAX_RETRIES: 3,
    UPSTREAM_RETRY_BASE_MS: 500,
    LOG_LEVEL: process.env.LOG_LEVEL || 'warn',
  };

  const { server, hub } = createServer(cfg);
  const gwPort = await listen(server, 0, '127.0.0.1');
  console.log(`Gateway sur http://127.0.0.1:${gwPort}`);
  console.log(
    `Paramètres : ${N_CLIENTS} clients (dont ${N_SLOW} lents), ` +
      `${mb(CHUNK_BYTES)} Mo/tick toutes les ${TICK_MS}ms, mesure ${RUN_MS}ms\n`,
  );

  // ---- Connexion des N clients sur LA MÊME chaîne (streamId = "1") ----------
  const received = new Array(N_CLIENTS).fill(0); // octets reçus par client
  const clientReqs = [];
  const slowSockets = [];

  for (let i = 0; i < N_CLIENTS; i += 1) {
    const isSlow = i < N_SLOW; // les N_SLOW premiers sont volontairement lents
    const req = http.get(
      {
        host: '127.0.0.1',
        port: gwPort,
        path: `/live/diff/diff/1.ts`, // MÊME chaîne pour tous → mutualisation
        agent: false, // une socket dédiée par client (réaliste)
      },
      (res) => {
        if (isSlow) {
          // Client lent : on met sa socket en pause → il n'absorbe plus rien.
          // Le tampon côté gateway va se remplir puis le backpressure le coupera,
          // SANS impacter les clients sains.
          res.pause();
          slowSockets.push(res);
        } else {
          res.on('data', (chunk) => {
            received[i] += chunk.length;
          });
        }
        res.on('error', () => {});
      },
    );
    req.on('error', () => {});
    clientReqs.push(req);
  }

  // Petite pause pour laisser les connexions s'établir.
  await new Promise((r) => setTimeout(r, 800));

  // ---- Fenêtre de mesure ---------------------------------------------------
  const t0 = Date.now();
  let peakBuffered = 0;
  let peakRss = 0;
  const sampler = setInterval(() => {
    const st = hub.stats();
    peakBuffered = Math.max(peakBuffered, st.totalBufferedBytes);
    peakRss = Math.max(peakRss, process.memoryUsage().rss);
  }, 200);

  await new Promise((r) => setTimeout(r, RUN_MS));
  clearInterval(sampler);
  const elapsed = (Date.now() - t0) / 1000;

  // ---- Relevé final --------------------------------------------------------
  const stats = hub.stats();
  const healthyIdx = [];
  for (let i = 0; i < N_CLIENTS; i += 1) if (i >= N_SLOW) healthyIdx.push(i);

  const healthyReceiving = healthyIdx.filter((i) => received[i] > 0).length;
  const totalHealthyBytes = healthyIdx.reduce((s, i) => s + received[i], 0);
  const avgThroughputMbps =
    (totalHealthyBytes * 8) / elapsed / 1e6; // agrégé sur clients sains

  console.log(c.b('───────────── RÉSULTATS ─────────────'));
  console.log(`Durée de mesure ............ ${elapsed.toFixed(1)} s`);
  console.log(`Connexions upstream (cumul)  ${upstreamConnections}`);
  console.log(`Connexions upstream actives  ${upstreamActive}`);
  console.log(`Abonnés vus par le hub ..... ${stats.totalSubscribers}`);
  console.log(`Chaînes ouvertes ........... ${stats.activeUpstreams} / ${stats.providerMax}`);
  console.log(`Clients sains recevant ..... ${healthyReceiving} / ${healthyIdx.length}`);
  console.log(`Débit agrégé (clients sains) ${avgThroughputMbps.toFixed(0)} Mbps`);
  console.log(`Tampon global crête ........ ${mb(peakBuffered)} Mo / ${mb(stats.globalBufferCap)} Mo`);
  console.log(`RSS process crête .......... ${mb(peakRss)} Mo`);
  console.log('');

  // ============================================================================
  // VÉRIFICATION DES INVARIANTS
  // ============================================================================
  const failures = [];

  // A. UNE SEULE connexion upstream (le cœur de la preuve).
  if (upstreamConnections !== 1) {
    failures.push(
      `A. Attendu 1 connexion upstream, observé ${upstreamConnections} ` +
        `(mutualisation cassée : chaque client tire sa propre connexion !)`,
    );
  } else {
    console.log(c.g(`✓ A. 1 seule connexion upstream pour ${N_CLIENTS} clients`));
  }

  // B. Les clients sains reçoivent bien des octets.
  if (healthyReceiving !== healthyIdx.length) {
    failures.push(
      `B. Seuls ${healthyReceiving}/${healthyIdx.length} clients sains reçoivent des octets`,
    );
  } else {
    console.log(c.g(`✓ B. Les ${healthyIdx.length} clients sains reçoivent des octets`));
  }

  // C. Mémoire bornée sous le plafond global.
  if (peakBuffered > stats.globalBufferCap) {
    failures.push(
      `C. Tampon global crête ${mb(peakBuffered)} Mo > plafond ${mb(stats.globalBufferCap)} Mo`,
    );
  } else {
    console.log(
      c.g(`✓ C. Mémoire bornée : crête ${mb(peakBuffered)} Mo < ${mb(stats.globalBufferCap)} Mo`),
    );
  }

  // D. Les clients lents n'ont pas bloqué les autres : ils doivent avoir été
  //    coupés par le backpressure (donc ne plus figurer parmi les abonnés), et
  //    les clients sains doivent toujours recevoir (vérifié en B).
  const slowStillSubscribed = stats.totalSubscribers > healthyIdx.length;
  if (N_SLOW > 0 && slowStillSubscribed) {
    failures.push(
      `D. ${stats.totalSubscribers - healthyIdx.length} client(s) lent(s) encore abonné(s) ` +
        `— le backpressure aurait dû les couper`,
    );
  } else {
    console.log(
      c.g(`✓ D. Client(s) lent(s) coupé(s) par le backpressure sans bloquer les sains`),
    );
  }

  // ---- BONUS : > PROVIDER_MAX_CONNECTIONS chaînes distinctes → 503 ----------
  console.log('');
  console.log(c.b('───── BONUS : chaîne distincte au-delà de la limite ─────'));
  const bonusOk = await testDistinctChannelRefused(gwPort);
  if (!bonusOk) {
    failures.push('E. Une 2ᵉ chaîne distincte aurait dû être refusée (503)');
  }

  // ---- Nettoyage -----------------------------------------------------------
  for (const req of clientReqs) req.destroy();
  for (const s of slowSockets) s.destroy();
  hub.close();
  server.close();
  fakeUpstream.close();
  for (const t of upstreamTimers) clearInterval(t);

  // ---- Verdict -------------------------------------------------------------
  console.log('');
  if (failures.length) {
    console.log(c.r(c.b('✗ ÉCHEC — invariants violés :')));
    for (const f of failures) console.log(c.r('  • ' + f));
    process.exit(1);
  }
  console.log(c.g(c.b('✓ SUCCÈS — 500 clients servis par 1 seule connexion upstream.')));
  console.log(
    c.b(
      `  Résumé chiffré : ${N_CLIENTS} clients • 1 upstream • ` +
        `${avgThroughputMbps.toFixed(0)} Mbps agrégés • ` +
        `${mb(peakBuffered)} Mo tampon crête • ${mb(peakRss)} Mo RSS crête`,
    ),
  );
  process.exit(0);
}

// Vérifie qu'une DEUXIÈME chaîne distincte est refusée proprement (503) tant
// que la première occupe l'unique connexion fournisseur.
function testDistinctChannelRefused(gwPort) {
  return new Promise((resolve) => {
    const req = http.get(
      { host: '127.0.0.1', port: gwPort, path: '/live/diff/diff/999.ts', agent: false },
      (res) => {
        const ok = res.statusCode === 503;
        console.log(
          ok
            ? c.g(`✓ E. Chaîne distincte "999" refusée proprement (HTTP ${res.statusCode})`)
            : c.r(`✗ E. Chaîne distincte "999" a répondu HTTP ${res.statusCode} (503 attendu)`),
        );
        res.resume();
        resolve(ok);
      },
    );
    req.on('error', () => resolve(false));
  });
}

main().catch((err) => {
  console.error(c.r('Erreur fatale du test : ' + err.stack));
  process.exit(1);
});
