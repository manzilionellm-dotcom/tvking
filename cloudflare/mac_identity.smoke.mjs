// =========================================================
//  mac_identity.smoke.mjs — changer / régénérer MAC
// =========================================================
//  Prouve les règles métier SANS D1 réelle :
//   1) normalizeMac accepte le numéro de référence affiché
//   2) generateVirtualMac = MK: + 5 octets uniques
//   3) classifyProblems : lifetime inactive + abo jouable
//   4) migrateDeviceMac : rename live + tombstone sans android_id
//   5) anti-freeloader : mac_taken / same_mac / already_superseded
//
//  Lancer : node cloudflare/mac_identity.smoke.mjs
// =========================================================
import assert from 'node:assert/strict';
import {
  normalizeMac, isValidMac, generateVirtualMac,
  classifyProblems, problemPredicates, migrateDeviceMac,
  MAC_OWNED_TABLES,
  formatMacAsYouType, formatMacInput, looksLikeMacTyping,
} from './mac_identity.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('  ✓', m); }
  else { fail++; console.log('  ✗', m); }
};

// ----- 1) Normalisation (numéro affiché = identité interne) -----
ok(normalizeMac('CD:18:EF:A1:A0') === 'MK:CD:18:EF:A1:A0',
  '1 référence affichée CD:18:EF:A1:A0 → MK:CD:18:EF:A1:A0');
ok(normalizeMac('mk:cd:18:ef:a1:a0') === 'MK:CD:18:EF:A1:A0',
  '1 MK: déjà présent, casse normalisée');
ok(normalizeMac('cd18efa1a0') === 'MK:CD:18:EF:A1:A0',
  '1 hex collé sans deux-points');
ok(isValidMac('CD:18:EF:A1:A0') && isValidMac('MK:CD:18:EF:A1:A0'),
  '1 les deux formes sont valides');
ok(!isValidMac('ZZ:PAS:UNE:MAC') && !isValidMac(''),
  '1 refuse le garbage');

// ----- 1b) Auto-`:` pendant la frappe (recherche Devices / collage) -----
ok(formatMacAsYouType('807860074F') === '80:78:60:07:4F',
  '1b 807860074F → 80:78:60:07:4F');
ok(formatMacAsYouType('80:78:60:07:4F') === '80:78:60:07:4F',
  '1b collage déjà ponctué inchangé');
ok(formatMacAsYouType('80-78-60-07-4F') === '80:78:60:07:4F',
  '1b collage avec tirets');
ok(formatMacAsYouType('MK807860074F') === 'MK:80:78:60:07:4F',
  '1b préfixe MK sans deux-points');
ok(formatMacAsYouType('mk:807860074f') === 'MK:80:78:60:07:4F',
  '1b MK: déjà là + hex nu');
ok(formatMacAsYouType('80') === '80',
  '1b premier octet incomplet');
ok(formatMacAsYouType('807') === '80:7',
  '1b : dès 3e hex');
ok(formatMacAsYouType('Jean') === 'Jean',
  '1b nom de client intact');
ok(formatMacAsYouType('Ada') === 'Ada',
  '1b Ada (lettres A–F seules) n’est pas une MAC');
ok(formatMacAsYouType('cafe') === 'cafe',
  '1b cafe sans chiffre reste un mot');
ok(looksLikeMacTyping('80') && !looksLikeMacTyping('Jean'),
  '1b looksLikeMacTyping distingue hex et nom');
ok(formatMacInput('CD:18:EF:A1:A0') === 'MK:CD:18:EF:A1:A0',
  '1b formatMacInput force MK: + 5 octets');
ok(formatMacInput('cd18efa1a0') === 'MK:CD:18:EF:A1:A0',
  '1b formatMacInput chiffres seuls');
ok(formatMacInput('MK:CD:18:EF:A1:A0') === 'MK:CD:18:EF:A1:A0',
  '1b formatMacInput déjà canonique');

// ----- 2) Génération -----
const a = generateVirtualMac();
const b = generateVirtualMac();
ok(/^MK(:[0-9A-F]{2}){5}$/.test(a), '2 format MK:XX:XX:XX:XX:XX');
ok(a !== b, '2 deux tirages distincts');
ok(isValidMac(a), '2 généré valide');

// ----- 3) Signaux problématiques -----
const now = 1_700_000_000_000;
const pred = problemPredicates(now);
ok(pred.problematic.includes('license_pick') || pred.license_pick.includes('expires_at IS NULL'),
  '3 prédicat lifetime / pick présent');
ok(pred.android_id_dup.includes('android_id'),
  '3 prédicat doublon android_id');
ok(pred.pending_reassign.includes('superseded_by'),
  '3 prédicat app pas encore migrée');
ok(MAC_OWNED_TABLES.some(([t]) => t === 'device_profiles'),
  '3 les profils (enfants) suivent la MAC');

const pick = classifyProblems({
  lic_count: 2,
  lifetime_masks: 1,
  android_id_siblings: 1,
  online_unpaid_flag: 0,
}, now);
ok(pick.includes('multi_license'), '3 multi_license détecté');
ok(pick.includes('lifetime_masks_active'), '3 lifetime inactive masque un abo');
ok(pick.includes('android_id_dup'), '3 android_id en double');

const tomb = classifyProblems({
  superseded_by: 'MK:AA:BB:CC:DD:EE',
  last_seen_at: now - 1000,
  presence_last_seen: now,
}, now);
ok(tomb.includes('pending_reassign') && tomb.length === 1,
  '3 tombstone récente = pending_reassign seul');

// ----- 4–5) migrateDeviceMac (faux D1) -----
function fakeDb(state) {
  const log = [];
  const db = {
    log,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async first() {
              log.push({ sql, args, kind: 'first' });
              if (/FROM devices WHERE mac/.test(sql) && /superseded_by/.test(sql)) {
                const mac = args[0];
                return state.byMac[mac] || null;
              }
              if (/FROM devices WHERE mac/.test(sql)) {
                const mac = args[0];
                return state.byMac[mac] || null;
              }
              if (/SELECT id FROM devices WHERE mac/.test(sql)) {
                const mac = args[0];
                const row = state.byMac[mac];
                return row ? { id: row.id } : null;
              }
              return null;
            },
            async run() {
              log.push({ sql, args, kind: 'run' });
              if (/UPDATE devices SET mac =/.test(sql)) {
                const [newMac, , , id] = args;
                const old = Object.values(state.byMac).find((d) => d.id === id);
                if (old) {
                  delete state.byMac[old.mac];
                  old.mac = newMac;
                  state.byMac[newMac] = old;
                }
              }
              if (/INSERT INTO devices/.test(sql)) {
                const id = args[0];
                const mac = args[2];
                state.byMac[mac] = {
                  id,
                  customer_id: args[1],
                  mac,
                  block_status: 'banned',
                  superseded_by: args[args.length - 1],
                  android_id: null,
                };
                state.tombstones.push(state.byMac[mac]);
              }
              return { success: true, meta: { changes: 1 } };
            },
            async all() { return { results: [] }; },
          };
        },
      };
    },
  };
  return db;
}

{
  const live = {
    id: 'dev_live1',
    customer_id: 'cus_1',
    reseller_id: 'res_1',
    first_seen_at: 100,
    android_id: 'AID-TABLETTE',
    admin_note: 'client Lionel',
    label: null,
    block_status: null,
    superseded_by: null,
    mac: 'MK:CD:18:EF:A1:A0',
  };
  const state = { byMac: { [live.mac]: { ...live } }, tombstones: [] };
  const env = { DB: fakeDb(state) };
  const r = await migrateDeviceMac(env, {
    oldMac: 'CD:18:EF:A1:A0', // forme affichée
    newMac: 'MK:11:22:33:44:55',
    now: 200,
  });
  ok(r.ok === true, '4 migrate OK');
  ok(r.old_mac === 'MK:CD:18:EF:A1:A0' && r.new_mac === 'MK:11:22:33:44:55',
    '4 normalise old + new');
  ok(r.device_id === 'dev_live1', '4 même device_id (licences suivent)');
  ok(state.byMac['MK:11:22:33:44:55']?.id === 'dev_live1',
    '4 fiche live porte le nouveau MAC');
  ok(state.byMac['MK:CD:18:EF:A1:A0']?.block_status === 'banned',
    '4 ancienne MAC tombstonée / bannie');
  ok(!state.byMac['MK:CD:18:EF:A1:A0']?.android_id,
    '4 tombstone SANS android_id (anti-héritage de ban)');
  ok(state.byMac['MK:CD:18:EF:A1:A0']?.superseded_by === 'MK:11:22:33:44:55',
    '4 superseded_by pointe vers le nouveau');
}

{
  const env = {
    DB: fakeDb({
      byMac: {
        'MK:AA:AA:AA:AA:AA': {
          id: 'dev_a', customer_id: 'c', reseller_id: null,
          first_seen_at: 1, android_id: null, admin_note: null,
          label: null, block_status: null, superseded_by: null,
          mac: 'MK:AA:AA:AA:AA:AA',
        },
        'MK:BB:BB:BB:BB:BB': {
          id: 'dev_b', customer_id: 'c2', reseller_id: null,
          first_seen_at: 1, android_id: null, admin_note: null,
          label: null, block_status: null, superseded_by: null,
          mac: 'MK:BB:BB:BB:BB:BB',
        },
      },
      tombstones: [],
    }),
  };
  const taken = await migrateDeviceMac(env, {
    oldMac: 'MK:AA:AA:AA:AA:AA',
    newMac: 'MK:BB:BB:BB:BB:BB',
  });
  ok(taken.error === 'mac_taken', '5 refuse d’écraser une MAC déjà vivante');

  const same = await migrateDeviceMac(env, {
    oldMac: 'MK:AA:AA:AA:AA:AA',
    newMac: 'MK:AA:AA:AA:AA:AA',
  });
  ok(same.error === 'same_mac', '5 refuse old === new');

  const gone = await migrateDeviceMac(env, {
    oldMac: 'MK:FF:FF:FF:FF:FF',
    newMac: 'MK:11:11:11:11:11',
  });
  ok(gone.error === 'not_found', '5 MAC inconnue → not_found');
}

{
  const env = {
    DB: fakeDb({
      byMac: {
        'MK:CC:CC:CC:CC:CC': {
          id: 'dev_old', customer_id: 'c', reseller_id: null,
          first_seen_at: 1, android_id: null, admin_note: null,
          label: null, block_status: 'banned',
          superseded_by: 'MK:DD:DD:DD:DD:DD',
          mac: 'MK:CC:CC:CC:CC:CC',
        },
      },
      tombstones: [],
    }),
  };
  const r = await migrateDeviceMac(env, {
    oldMac: 'MK:CC:CC:CC:CC:CC',
    newMac: 'MK:EE:EE:EE:EE:EE',
  });
  ok(r.error === 'already_superseded', '5 on ne re-migre pas un tombstone');
}

console.log(`\nmac_identity.smoke : ${pass} ok, ${fail} ko`);
if (fail) process.exit(1);
