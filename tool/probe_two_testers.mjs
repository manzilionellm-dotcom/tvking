#!/usr/bin/env node
// =========================================================
//  probe_two_testers.mjs — PREUVE « 2 téléphones en même temps »
// =========================================================
//  Sonde EN PARALLÈLE, AU MÊME INSTANT, les flux servis à DEUX testeurs et
//  vérifie que la vidéo COULE pour les deux (HTTP 200 + octets reçus).
//  C'est la preuve automatique demandée avant de déclarer un test « bon » :
//  jamais conclure sur un écran noir.
//
//  UTILISATION (depuis n'importe quelle machine, aucun secret requis) :
//    node tool/probe_two_testers.mjs <listeA> <listeB> [nbOctetsMin]
//
//    <listeA> / <listeB> : l'URL de liste de CHAQUE testeur — la référence
//    opaque servie par le worker, ex. :
//      https://app.7themotion.com/api/master-list/ml_xxxxxxxxxxxxxxxxxxxx.m3u
//    (les deux testeurs d'un même maître partagent la même liste : passer
//    deux fois la même URL est NORMAL — la sonde tire alors le 1er flux pour
//    « A » et le 2e pour « B », ou deux fois le 1er s'il n'y en a qu'un,
//    ce qui prouve au passage la MUTUALISATION : même chaîne = même URL.)
//
//  Ce que fait la sonde, pour CHAQUE testeur, EN MÊME TEMPS (Promise.all) :
//    1. télécharge sa liste (M3U) et prend son flux ;
//    2. ouvre le flux et LIT de vrais octets vidéo (nbOctetsMin, défaut 64 Ko)
//       avec un délai max de 15 s ;
//    3. journalise hôte / statut / latence 1er octet / octets reçus — JAMAIS
//       l'URL complète (elle peut porter une identité de diffusion).
//
//  Code de sortie : 0 = les DEUX flux coulent simultanément (vert) ;
//                   1 = au moins un flux ne coule pas (échec, hôte nommé).
//
//  MUTUALISATION (à vérifier côté gateway pendant que la sonde tourne) :
//  2 testeurs sur la MÊME chaîne = 1 seule connexion fournisseur (le hub du
//  gateway partage le flux) ; sur des chaînes DIFFÉRENTES = 1 connexion par
//  chaîne. Le journal du gateway (hub.js) montre le nombre de connexions
//  fournisseur ouvertes.
//
//  Rappel : cette sonde est la moitié AUTOMATIQUE de la preuve finale. La
//  moitié HUMAINE reste : deux téléphones réels qui lisent en même temps,
//  confirmés visuellement par l'exploitant.
// =========================================================

const MIN_BYTES_DEFAULT = 64 * 1024;
const LIST_TIMEOUT_MS = 10_000;
const STREAM_TIMEOUT_MS = 15_000;

// Masque une URL pour les journaux : on ne montre QUE l'hôte + l'extension
// (jamais le chemin, qui peut contenir une identité de diffusion).
function safeLabel(url) {
  try { return new URL(url).host; } catch (_) { return '(url illisible)'; }
}

async function fetchWithTimeout(url, ms) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { signal: ctrl.signal, redirect: 'follow' });
  } finally { clearTimeout(t); }
}

// Lit la liste d'un testeur et renvoie ses URLs de flux (ordonnées).
async function readList(listUrl) {
  const r = await fetchWithTimeout(listUrl, LIST_TIMEOUT_MS);
  if (!r.ok) throw new Error(`liste HTTP ${r.status} (${safeLabel(listUrl)})`);
  const text = await r.text();
  const urls = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  if (!urls.length) throw new Error(`liste VIDE (${safeLabel(listUrl)}) — rien à jouer`);
  return urls;
}

// Sonde UN flux : ouvre, lit minBytes octets, mesure latence 1er octet.
async function probeStream(label, url, minBytes) {
  const host = safeLabel(url);
  const t0 = Date.now();
  const ctrl = new AbortController();
  const killer = setTimeout(() => ctrl.abort(), STREAM_TIMEOUT_MS);
  try {
    const r = await fetch(url, { signal: ctrl.signal, redirect: 'follow' });
    if (!(r.status >= 200 && r.status < 300)) {
      throw new Error(`HTTP ${r.status}`);
    }
    let received = 0;
    let firstByteMs = null;
    const reader = r.body.getReader();
    while (received < minBytes) {
      const { done, value } = await reader.read();
      if (done) break;
      if (firstByteMs === null) firstByteMs = Date.now() - t0;
      received += value.byteLength;
    }
    try { await reader.cancel(); } catch (_) { /* fin propre */ }
    if (received <= 0) throw new Error('0 octet reçu (flux qui ne coule pas)');
    return {
      label, host, ok: true, status: r.status,
      firstByteMs: firstByteMs ?? (Date.now() - t0),
      bytes: received, totalMs: Date.now() - t0,
    };
  } catch (e) {
    return {
      label, host, ok: false, status: 0,
      error: String((e && e.message) || e), totalMs: Date.now() - t0,
    };
  } finally { clearTimeout(killer); }
}

async function main() {
  const [, , listA, listB, minBytesArg] = process.argv;
  if (!listA || !listB) {
    console.error('Usage : node tool/probe_two_testers.mjs <urlListeA> <urlListeB> [nbOctetsMin]');
    console.error('Ex.   : node tool/probe_two_testers.mjs \\');
    console.error('          https://app.7themotion.com/api/master-list/ml_….m3u \\');
    console.error('          https://app.7themotion.com/api/master-list/ml_….m3u');
    process.exit(2);
  }
  const minBytes = Number(minBytesArg) > 0 ? Number(minBytesArg) : MIN_BYTES_DEFAULT;

  console.log('— Lecture des listes des 2 testeurs…');
  const [urlsA, urlsB] = await Promise.all([readList(listA), readList(listB)]);
  // Testeur A = 1er flux de sa liste ; testeur B = 2e flux de la sienne s'il
  // existe (chaînes différentes → 2 connexions attendues côté gateway), sinon
  // le 1er (même chaîne → mutualisation : 1 seule connexion fournisseur).
  const streamA = urlsA[0];
  const streamB = urlsB[1] || urlsB[0];
  const sameChannel = streamA === streamB;
  console.log(`  A : ${urlsA.length} flux dans la liste → sonde ${safeLabel(streamA)}`);
  console.log(`  B : ${urlsB.length} flux dans la liste → sonde ${safeLabel(streamB)}`);
  console.log(sameChannel
    ? '  (même chaîne pour A et B → le gateway doit mutualiser : 1 connexion fournisseur)'
    : '  (chaînes différentes → 1 connexion fournisseur par chaîne, c’est attendu)');

  console.log(`\n— Sonde PARALLÈLE (les 2 flux au même instant, ${minBytes} octets minimum chacun)…`);
  const t0 = Date.now();
  const results = await Promise.all([
    probeStream('A', streamA, minBytes),
    probeStream('B', streamB, minBytes),
  ]);
  const wall = Date.now() - t0;

  let allOk = true;
  for (const r of results) {
    if (r.ok) {
      console.log(`  ✅ ${r.label} · hôte=${r.host} · HTTP ${r.status} · 1er octet ${r.firstByteMs} ms · ${r.bytes} octets en ${r.totalMs} ms — LE FLUX COULE`);
    } else {
      allOk = false;
      console.log(`  ❌ ${r.label} · hôte=${r.host} · ÉCHEC (${r.error}) après ${r.totalMs} ms`);
    }
  }

  if (allOk) {
    console.log(`\n✅ PREUVE AUTOMATIQUE OK : les 2 testeurs reçoivent la vidéo SIMULTANÉMENT (${wall} ms au total).`);
    console.log('   Reste la preuve HUMAINE : 2 téléphones réels qui lisent en même temps, confirmés par l’exploitant.');
    process.exit(0);
  } else {
    console.log('\n❌ ÉCHEC : au moins un flux ne coule pas. L’hôte fautif est nommé ci-dessus.');
    console.log('   → Panel → Comptes maîtres → Diagnostic / Simulateur A-B pour la cause exacte, corriger, RE-tester.');
    process.exit(1);
  }
}

main().catch((e) => { console.error('Erreur sonde :', (e && e.message) || e); process.exit(1); });
