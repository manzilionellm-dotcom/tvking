// =========================================================
//  family_positions.smoke.mjs — Famille : qui regarde, chacun son film
// =========================================================
//  Le VRAI worker.js, avec une D1 simulée en mémoire. Ce qui est verrouillé :
//
//    1. /api/family/info dit QUI est en lecture (booléen), pour le
//       propriétaire ET pour un membre — sans jamais le nom de la chaîne.
//    2. /api/family/positions : les positions de reprise d'un profil sont
//       partagées entre les appareils de la famille (même clé = MAC du
//       propriétaire), fusion « le plus récent gagne », terminé propagé.
//    3. Un appareil hors famille se synchronise avec lui-même (clé = sa MAC)
//       et ne voit JAMAIS les positions d'une autre famille.
//    4. Les entrées invalides (profil, clé, horodatage futur, position
//       au-delà de la durée) sont ignorées sans casser les autres.
//    5. /api/device-profiles : un membre lit les profils du propriétaire.
//
//  Exécution : node cloudflare/family_positions.smoke.mjs
// =========================================================
import worker from './worker.js';

const OWNER = 'MK:AA:AA:AA:AA:01';
const MEMBER = 'MK:AA:AA:AA:AA:02';
const STRANGER = 'MK:BB:BB:BB:BB:01';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

// ---- D1 simulée ---------------------------------------------------------
const links = new Map([[MEMBER, { owner_mac: OWNER, label: 'Papa', created_at: 1 }]]);
const plans = new Map([[OWNER, { enabled: 1, max_members: 4 }]]);
const presence = new Map(); // mac -> {last_seen, playing}
const positions = new Map(); // fam|profile|key -> row
const profiles = new Map(); // mac -> profiles_json
const db = {
  prepare(sql) {
    return {
      _sql: sql, _args: [],
      bind(...a) { this._args = a; return this; },
      async run() {
        const s = this._sql; const a = this._args;
        if (/INSERT INTO app_family_positions/.test(s)) {
          const k = `${a[0]}|${a[1]}|${a[2]}`;
          const prev = positions.get(k);
          if (!prev || a[6] > prev.updated_at) {
            positions.set(k, {
              family_mac: a[0], profile_id: a[1], content_key: a[2], position_ms: a[3],
              duration_ms: a[4], finished: a[5], updated_at: a[6], name: a[7],
              poster_url: a[8], is_episode: a[9],
            });
          }
        } else if (/INSERT INTO device_profiles/.test(s)) {
          profiles.set(a[0], a[1]);
        }
        return { success: true };
      },
      async first() {
        const s = this._sql; const a = this._args;
        if (/FROM app_family_links l/.test(s)) {
          const l = links.get(a[0]);
          if (!l) return null;
          const p = plans.get(l.owner_mac);
          return p && p.enabled === 1 ? { owner_mac: l.owner_mac } : null;
        }
        if (/FROM app_family_plan WHERE owner_mac/.test(s)) return plans.get(a[0]) || null;
        if (/FROM app_family_codes/.test(s)) return null;
        if (/FROM device_profiles WHERE mac/.test(s)) {
          const j = profiles.get(a[0]);
          return j ? { profiles_json: j } : null;
        }
        return null;
      },
      async all() {
        const s = this._sql; const a = this._args;
        if (/FROM app_family_links WHERE owner_mac/.test(s)) {
          const results = [];
          for (const [m, l] of links) if (l.owner_mac === a[0]) results.push({ member_mac: m, ...l });
          return { results };
        }
        if (/FROM presence WHERE mac IN/.test(s)) {
          return { results: a.filter((m) => presence.has(m)).map((m) => ({ mac: m, ...presence.get(m) })) };
        }
        if (/FROM app_family_positions WHERE family_mac = \? AND profile_id = \?/.test(s)) {
          const results = [...positions.values()]
            .filter((r) => r.family_mac === a[0] && r.profile_id === a[1])
            .sort((x, y) => y.updated_at - x.updated_at)
            .slice(0, a[2]);
          return { results };
        }
        return { results: [] };
      },
    };
  },
};
const env = { DB: db };
const ctx = { waitUntil() {}, passThroughOnException() {} };
const call = (path, opts = {}) => worker.fetch(
  new Request('https://app.x' + path, {
    method: opts.method || 'GET',
    headers: opts.body ? { 'Content-Type': 'application/json' } : {},
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  }), env, ctx,
);
const NOW = Date.now();

// =========================================================
console.log('\n1. Qui regarde en ce moment (sans le nom de la chaîne)');
// =========================================================
presence.set(OWNER, { last_seen: NOW - 30_000, playing: 1 });
presence.set(MEMBER, { last_seen: NOW - 20 * 60_000, playing: 1 }); // trop vieux
let r = await call('/api/family/info/' + OWNER);
let b = await r.json();
ok(r.status === 200 && b.ok === true && b.role === 'owner', 'vue propriétaire (statut ' + r.status + ')');
ok(Array.isArray(b.who) && b.who.length === 2, 'who = cet appareil + 1 proche');
const me = b.who.find((w) => w.me);
const papa = b.who.find((w) => !w.me);
ok(me && me.playing === true && me.online === true, 'le propriétaire est « en lecture »');
ok(papa && papa.label === 'Papa' && papa.online === false && papa.playing === false,
  'un proche vu il y a 20 min est « hors ligne », donc pas en lecture');
ok(!JSON.stringify(b.who).includes('channel'), 'aucun nom de chaîne dans who');
ok(papa && typeof papa.ref === 'string' && !JSON.stringify(b.who).includes(MEMBER),
  'la MAC du proche ne sort pas en clair');

r = await call('/api/family/info/' + MEMBER);
b = await r.json();
ok(b.role === 'member' && Array.isArray(b.who) && b.who.length === 2, 'vue membre : propriétaire + proches');
ok(b.who.some((w) => w.role === 'owner' && w.playing === true),
  'le membre voit que le propriétaire regarde (la ligne est prise)');
ok(b.who.some((w) => w.me === true && w.role === 'member'), 'le membre se reconnaît (me = true)');

// =========================================================
console.log('\n2. Positions de reprise partagées dans la famille');
// =========================================================
r = await call('/api/family/positions/' + OWNER, {
  method: 'PUT',
  body: { profile: 'papa', items: [
    { key: 'vod-100', position_ms: 600_000, duration_ms: 6_000_000, updated_at: NOW - 5000, name: 'Film A' },
    { key: 'ep-7', position_ms: 120_000, duration_ms: 2_400_000, updated_at: NOW - 4000, name: 'S1 E2', is_episode: true },
  ] },
});
b = await r.json();
ok(r.status === 200 && b.ok === true && b.accepted === 2, 'le propriétaire pousse deux positions (accepted=' + b.accepted + ')');

r = await call('/api/family/positions/' + MEMBER + '?profile=papa');
b = await r.json();
ok(b.ok === true && b.items.length === 2, 'le membre lit les DEUX positions du même profil');
ok(b.family && !b.family.includes('AA:AA:AA:AA:01'.slice(0, 8)), 'clé de famille masquée dans la réponse');
ok(b.items[0].key === 'ep-7', 'plus récent d\'abord');
ok(!JSON.stringify(b).includes('stream'), 'aucune URL de flux stockée ni renvoyée');

// Le membre avance dans le film sur son téléphone → plus récent → gagne.
r = await call('/api/family/positions/' + MEMBER, {
  method: 'PUT',
  body: { profile: 'papa', items: [
    { key: 'vod-100', position_ms: 1_800_000, duration_ms: 6_000_000, updated_at: NOW - 1000, name: 'Film A' },
  ] },
});
b = await (await call('/api/family/positions/' + OWNER + '?profile=papa')).json();
const filmA = b.items.find((i) => i.key === 'vod-100');
ok(filmA && filmA.position_ms === 1_800_000, 'la TV voit la position avancée sur le téléphone');

// Une position PLUS ANCIENNE ne doit pas écraser la plus récente.
await call('/api/family/positions/' + OWNER, {
  method: 'PUT',
  body: { profile: 'papa', items: [
    { key: 'vod-100', position_ms: 300_000, duration_ms: 6_000_000, updated_at: NOW - 9000, name: 'Film A' },
  ] },
});
b = await (await call('/api/family/positions/' + OWNER + '?profile=papa')).json();
ok(b.items.find((i) => i.key === 'vod-100').position_ms === 1_800_000, 'le plus récent gagne, l\'ancien est ignoré');

// Terminé sur un appareil → l'autre le sait.
await call('/api/family/positions/' + MEMBER, {
  method: 'PUT',
  body: { profile: 'papa', items: [{ key: 'ep-7', finished: true, updated_at: NOW - 500 }] },
});
b = await (await call('/api/family/positions/' + OWNER + '?profile=papa')).json();
ok(b.items.find((i) => i.key === 'ep-7').finished === true, '« terminé » se propage à la famille');

// Les profils sont cloisonnés : « maman » ne voit pas les films de « papa ».
b = await (await call('/api/family/positions/' + OWNER + '?profile=maman')).json();
ok(b.ok === true && b.items.length === 0, 'le profil maman a sa propre liste, vide');

// =========================================================
console.log('\n3. Un appareil hors famille reste chez lui');
// =========================================================
await call('/api/family/positions/' + STRANGER, {
  method: 'PUT',
  body: { profile: 'papa', items: [{ key: 'vod-999', position_ms: 100_000, duration_ms: 900_000, updated_at: NOW - 100 }] },
});
b = await (await call('/api/family/positions/' + STRANGER + '?profile=papa')).json();
ok(b.family === null && b.items.length === 1 && b.items[0].key === 'vod-999', 'sa clé = sa MAC, ses positions à lui');
b = await (await call('/api/family/positions/' + OWNER + '?profile=papa')).json();
ok(!b.items.some((i) => i.key === 'vod-999'), 'la famille ne voit pas les positions de l\'inconnu');

// =========================================================
console.log('\n4. Entrées invalides ignorées sans casser les autres');
// =========================================================
r = await call('/api/family/positions/' + OWNER, {
  method: 'PUT',
  body: { profile: 'papa', items: [
    { key: 'bad key with spaces', position_ms: 1, duration_ms: 10, updated_at: NOW },
    { key: 'vod-future', position_ms: 1, duration_ms: 10, updated_at: NOW + 3 * 24 * 3600 * 1000 },
    { key: 'vod-over', position_ms: 50, duration_ms: 10, updated_at: NOW },
    { key: 'vod-okk', position_ms: 5, duration_ms: 10, updated_at: NOW },
  ] },
});
b = await r.json();
ok(b.accepted === 1, 'une seule entrée valide acceptée sur quatre (accepted=' + b.accepted + ')');
r = await call('/api/family/positions/' + OWNER, { method: 'PUT', body: { profile: 'Pas Valide!', items: [] } });
ok(r.status === 400, 'profil invalide → 400');
r = await call('/api/family/positions/' + OWNER + '?profile=papa', { method: 'DELETE' });
ok(r.status === 400, 'méthode inconnue → 400');

// =========================================================
console.log('\n5. Un membre lit les profils du propriétaire');
// =========================================================
b = await (await call('/api/device-profiles/' + OWNER)).json();
ok(b.available === true && b.profiles.length === 5 && b.family === null, 'le propriétaire a ses cinq profils');
const bm = await (await call('/api/device-profiles/' + MEMBER)).json();
ok(bm.available === true && JSON.stringify(bm.profiles) === JSON.stringify(b.profiles),
  'le membre voit EXACTEMENT les profils du propriétaire');
ok(typeof bm.family === 'string' && !bm.family.includes(OWNER.slice(3, 11)), 'famille signalée, MAC masquée');
ok(!profiles.has(MEMBER), 'aucun jeu de profils fantôme créé pour le membre');

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
