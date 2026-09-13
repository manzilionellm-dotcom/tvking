// =========================================================
//  mac_identity.js — Changer / régénérer l'identité MAC
// =========================================================
//  POURQUOI CE MODULE. Lionel a des MAC « zombies » : licences
//  conflictuelles, lifetime inactive qui masque un abo frais, doublons
//  android_id… Transférer vers une MAC déjà affichée dans l'app ne
//  suffit pas : l'app GARDE son ancien numéro (SharedPreferences) et
//  le heartbeat continue de viser le zombie.
//
//  Ici on crée une IDENTITÉ NEUVE (MK:xx:…), on y DÉMÉNAGE tout ce
//  que le client possède, on TOMBSTONE l'ancienne (bannie, sans
//  android_id → anti-freeloader), et on pousse `mac_reassigned`
//  pour que l'app mobile ADOPTE le nouveau numéro.
//
//  « Nouveau MAC » ≠ label UI : c'est la clé devices.mac, sources,
//  heartbeat, RT. Une seule vérité.
// =========================================================

/// Format canonique interne : MK + 5 octets (celui que l'app stocke).
export const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

/// Numéro de RÉFÉRENCE affiché (sans MK:) — ce que le client lit
/// sur « YOUR REFERENCE NUMBER » / dicte au téléphone.
const REF_RX = /^([0-9A-F]{2}:){4}[0-9A-F]{2}$/i;

/// Normalise une saisie humaine → MK:XX:XX:XX:XX:XX.
///
///  Accepte :
///   • MK:CD:18:EF:A1:A0  (interne)
///   • CD:18:EF:A1:A0     (affiché, stripPrefix)
///   • cd18efa1a0         (collé sans deux-points)
///  Sinon renvoie la chaîne upper-case telle quelle (l'appelant valide).
export function normalizeMac(raw) {
  const t = String(raw || '').trim().toUpperCase().replace(/\s+/g, '');
  if (MAC_RX.test(t)) return t;
  if (REF_RX.test(t)) return 'MK:' + t;
  const hex = t.replace(/^MK:?/, '').replace(/[^0-9A-F]/g, '');
  if (hex.length === 10) {
    return 'MK:' + hex.match(/.{2}/g).join(':');
  }
  return t;
}

export function isValidMac(raw) {
  return MAC_RX.test(normalizeMac(raw));
}

/// Vrai si la saisie ressemble à un début de MAC, pas à un nom.
/// Copie alignée sur `admin-panel/src/lib/utils.ts` — si tu changes
/// l'un, change l'autre (sinon le panel pose les `:` et le LIKE
/// Worker ne retrouve plus la ligne).
export function looksLikeMacTyping(raw) {
  const t = String(raw || '').trim();
  if (!t) return false;
  const mk = /^MK:?/i.test(t);
  const rest = mk ? t.replace(/^MK:?/i, '') : t;
  if (/[^0-9A-Fa-f:.\-\s]/.test(rest)) return false;
  const hex = rest.replace(/[^0-9A-Fa-f]/g, '');
  if (mk) return true;
  if (!hex) return false;
  if (/[0-9]/.test(hex)) return true;
  if (/[:.\-]/.test(rest)) return true;
  return false;
}

/// Pose les `:` tous les 2 hex pendant la frappe / un collage.
/// Max 6 octets ; préfixe `MK:` conservé s'il est déjà là.
/// `807860074F` → `80:78:60:07:4F` ; `Jean` → `Jean`.
export function formatMacAsYouType(raw) {
  const s = String(raw || '');
  if (!s) return '';
  if (!looksLikeMacTyping(s)) return s;

  const mk = /^MK:?/i.test(s.trimStart());
  const body = mk ? s.replace(/^\s*MK:?/i, '') : s;
  const hex = body.toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, 12);
  const pairs = hex.match(/.{1,2}/g) || [];
  const joined = pairs.join(':');
  if (mk) return joined ? `MK:${joined}` : 'MK:';
  return joined;
}

/// Champ dédié MAC → toujours `MK:` + 5 octets (contrat MAC_RX).
/// Même helper que le panel (`formatMacInput`).
export function formatMacInput(raw) {
  const s = String(raw || '');
  const seeded = /^MK/i.test(s.trim()) ? s : `MK:${s}`;
  const typed = formatMacAsYouType(seeded);
  const hexOnly = typed.toUpperCase().replace(/^MK:?/, '').replace(/[^0-9A-F]/g, '');
  const pairs = hexOnly.slice(0, 10).match(/.{1,2}/g) || [];
  return 'MK:' + pairs.join(':');
}

/// Génère un MAC virtuel propre (5 octets crypto-aléatoires).
/// Collision astronomiquement rare ; l'appelant revérifie en base.
export function generateVirtualMac() {
  const bytes = new Uint8Array(5);
  // Node + Worker : getRandomValues est partout.
  (globalThis.crypto || crypto).getRandomValues(bytes);
  const oct = [...bytes].map((b) => b.toString(16).padStart(2, '0').toUpperCase());
  return 'MK:' + oct.join(':');
}

export function genDeviceId() {
  const uuid = (globalThis.crypto || crypto).randomUUID();
  return 'dev_' + uuid.replace(/-/g, '').slice(0, 18);
}

/// Tables dont la MAC est une POSSESSION du client (même liste que
/// le transfert historique). On DÉPLACE, on ne réécrit pas les
/// journaux (credit_ledger, audit) — une trace datée ne se falsifie pas.
export const MAC_OWNED_TABLES = [
  ['device_orders', 'mac'],
  ['device_messages', 'mac'],
  ['device_profiles', 'mac'],
  ['device_backups', 'mac'],
  ['family_members', 'mac'],
  ['app_family_links', 'member_mac'],
  ['app_family_links', 'owner_mac'],
  ['master_test_list', 'mac'],
  ['app_masters', 'mac'],
];

/// Signaux D1 d'une MAC « problématique » — les vrais pièges Lionel.
/// `now` = Date.now() interpolé (jamais de saisie user).
export function problemPredicates(now) {
  const hunt = now - 24 * 60 * 60 * 1000;
  const trialWindow = now - 7 * 24 * 60 * 60 * 1000;
  const live =
    `(l.id IS NOT NULL AND IFNULL(l.status,'active') = 'active'` +
    ` AND (l.expires_at IS NULL OR l.expires_at > ${now}))`;
  const expired =
    `(l.id IS NOT NULL AND ((l.expires_at IS NOT NULL AND l.expires_at <= ${now})` +
    ` OR l.status = 'expired'))`;
  const recent =
    `(IFNULL(p.last_seen, 0) > ${hunt} OR d.last_seen_at > ${hunt})`;
  const onlineUnpaid =
    `(${recent} AND NOT ${live}` +
    ` AND (${expired} OR (l.id IS NULL AND IFNULL(d.first_seen_at,0) <= ${trialWindow}))` +
    ` AND (d.block_status IS NULL OR d.block_status = '' OR d.block_status = 'active')` +
    ` AND IFNULL(d.superseded_by,'') = '')`;

  // La JOIN actuelle prend lifetime D'ABORD, même inactive → paid=false
  // alors que /activate vient de poser un annuel jouable. C'est LE bug
  // « Activer OK / tablette verrouillée ».
  const pickedDead =
    `(l.id IS NOT NULL AND NOT (` +
      `IFNULL(l.status,'active') = 'active'` +
      ` AND (l.expires_at IS NULL OR l.expires_at > ${now})` +
    `))`;
  const otherLive =
    `EXISTS (SELECT 1 FROM licenses a WHERE a.device_id = d.id AND a.id != l.id` +
    ` AND IFNULL(a.status,'active') = 'active'` +
    ` AND (a.expires_at IS NULL OR a.expires_at > ${now}))`;
  const lifetimeMasksActive =
    `(${pickedDead} AND l.expires_at IS NULL AND ${otherLive})`;
  const licensePick = `(${pickedDead} AND ${otherLive})`;

  const multiLicense =
    `(SELECT COUNT(*) FROM licenses lx WHERE lx.device_id = d.id) > 1`;
  const androidDup =
    `(IFNULL(d.android_id,'') != '' AND EXISTS (` +
      `SELECT 1 FROM devices d2 WHERE d2.android_id = d.android_id` +
      ` AND d2.id != d.id AND IFNULL(d2.superseded_by,'') = ''))`;
  const pendingReassign =
    `(IFNULL(d.superseded_by,'') != '' AND ${recent})`;

  const problematic =
    `(${onlineUnpaid} OR ${licensePick} OR ${multiLicense}` +
    ` OR ${androidDup} OR ${pendingReassign})`;

  return {
    live,
    expired,
    recent,
    online_unpaid: onlineUnpaid,
    lifetime_masks_active: lifetimeMasksActive,
    license_pick: licensePick,
    multi_license: multiLicense,
    android_id_dup: androidDup,
    pending_reassign: pendingReassign,
    problematic,
  };
}

/// Classe les problèmes d'une ligne déjà lue (compteurs + pastilles).
export function classifyProblems(row, now = Date.now()) {
  const out = [];
  if (!row) return out;
  if (row.superseded_by) {
    const hunt = now - 24 * 60 * 60 * 1000;
    const last = Math.max(row.presence_last_seen || 0, row.last_seen_at || 0);
    if (last > hunt) out.push('pending_reassign');
    else out.push('superseded');
    return out; // tombstone : pas les autres bruits
  }
  const licCount = Number(row.lic_count || 0);
  if (licCount > 1) out.push('multi_license');
  if (Number(row.android_id_siblings || 0) > 0) out.push('android_id_dup');
  if (row.lifetime_masks) out.push('lifetime_masks_active');
  else if (row.license_pick) out.push('license_pick');
  if (row.online_unpaid_flag) out.push('online_unpaid');
  return out;
}

export const PROBLEM_LABELS = {
  multi_license: 'Plusieurs licences',
  android_id_dup: 'android_id en double',
  lifetime_masks_active: 'Lifetime inactive masque un abo',
  license_pick: 'Licence lue ≠ licence jouable',
  online_unpaid: 'En ligne sans abo',
  pending_reassign: 'MAC remplacée, app pas encore migrée',
  superseded: 'MAC remplacée (tombstone)',
};

/// Crée la colonne superseded_by (idempotent, même pattern qu'admin_note).
export async function ensureSupersededColumn(env) {
  if (!env || !env.DB) return;
  try {
    await env.DB.prepare(
      'ALTER TABLE devices ADD COLUMN superseded_by TEXT',
    ).run();
  } catch (_) { /* déjà là */ }
}

/// Déplace les possessions MAC (DELETE cible puis UPDATE source).
/// Chaque table dans son try : une base fraîche n'a pas tout créé.
export async function moveOwnedMacRows(env, oldMac, newMac, now) {
  const moved = [];
  try {
    await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(newMac).run();
    const src = await env.DB
      .prepare('UPDATE device_sources SET mac = ?, updated_at = ? WHERE mac = ?')
      .bind(newMac, now, oldMac).run();
    const n = src?.meta?.changes || 0;
    if (n > 0) moved.push(`device_sources.mac:${n}`);
  } catch (_) { /* pas de source */ }

  for (const [table, col] of MAC_OWNED_TABLES) {
    try {
      await env.DB.prepare(`DELETE FROM ${table} WHERE ${col} = ?`)
        .bind(newMac).run();
      const r = await env.DB
        .prepare(`UPDATE ${table} SET ${col} = ? WHERE ${col} = ?`)
        .bind(newMac, oldMac).run();
      const n = r?.meta?.changes || 0;
      if (n > 0) moved.push(`${table}.${col}:${n}`);
    } catch (_) { /* table absente */ }
  }

  // Présence : on EFFACE l'ancienne (faux « en ligne » sinon).
  try {
    await env.DB.prepare('DELETE FROM presence WHERE mac = ?').bind(oldMac).run();
  } catch (_) { /* pas de présence */ }

  return moved;
}

/// Migre l'identité : RENOMME la fiche live, TOMBSTONE l'ancienne.
///
///  Anti-freeloader (non négociable) :
///   • l'ancienne MAC reste en base, bannie, SANS android_id
///     (sinon ensureD1Device hériterait le ban sur le nouveau) ;
///   • superseded_by pointe vers le nouveau → heartbeat / status
///     renvoient mac_reassigned au lieu d'un simple verrou ;
///   • first_seen_at + android_id restent sur la fiche LIVE
///     (pas de 2e essai, pas de perte d'historique).
///
///  Si `newMac` est déjà une AUTRE fiche → { error: 'mac_taken' }.
///  On ne fusionne pas à l'aveugle (ce serait le transfert, autre geste).
export async function migrateDeviceMac(env, {
  oldMac,
  newMac,
  now = Date.now(),
  label = null,
}) {
  const from = normalizeMac(oldMac);
  const to = normalizeMac(newMac);
  if (!MAC_RX.test(from)) return { error: 'bad_old_mac' };
  if (!MAC_RX.test(to)) return { error: 'bad_new_mac' };
  if (from === to) return { error: 'same_mac' };

  await ensureSupersededColumn(env);

  let oldDev;
  try {
    oldDev = await env.DB
      .prepare(
        'SELECT id, customer_id, reseller_id, first_seen_at, android_id, admin_note, label, block_status, superseded_by' +
        ' FROM devices WHERE mac = ?',
      )
      .bind(from).first();
  } catch (_) {
    oldDev = await env.DB
      .prepare(
        'SELECT id, customer_id, reseller_id, first_seen_at, android_id, admin_note, label, block_status' +
        ' FROM devices WHERE mac = ?',
      )
      .bind(from).first();
  }
  if (!oldDev) return { error: 'not_found' };
  if (oldDev.superseded_by) return { error: 'already_superseded' };

  const clash = await env.DB
    .prepare('SELECT id FROM devices WHERE mac = ?')
    .bind(to).first();
  if (clash && clash.id !== oldDev.id) {
    return { error: 'mac_taken', existing_id: clash.id };
  }

  // 1) Renomme la fiche LIVE (même id → licences inchangées).
  await env.DB.prepare(
    'UPDATE devices SET mac = ?, label = COALESCE(?, label), last_seen_at = ?, ' +
    "block_status = NULL, superseded_by = NULL WHERE id = ?",
  ).bind(to, label || null, now, oldDev.id).run();

  // 2) Tombstone : ancienne adresse, bannie, SANS android_id.
  const tombId = genDeviceId();
  const note =
    `MAC remplacée le ${new Date(now).toISOString()} → ${to}` +
    (oldDev.admin_note ? ` | ${oldDev.admin_note}` : '');
  try {
    await env.DB.prepare(
      `INSERT INTO devices
        (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at,
         block_status, admin_note, superseded_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'banned', ?, ?)`,
    ).bind(
      tombId,
      oldDev.customer_id,
      from,
      'MAC remplacée',
      oldDev.reseller_id,
      oldDev.first_seen_at || now,
      now,
      note.slice(0, 2000),
      to,
    ).run();
  } catch (e) {
    // Colonne manquante malgré l'ALTER : on retente sans superseded_by
    // (le note + ban restent le filet anti-freeloader).
    try {
      await env.DB.prepare(
        `INSERT INTO devices
          (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at,
           block_status, admin_note)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'banned', ?)`,
      ).bind(
        tombId, oldDev.customer_id, from, 'MAC remplacée',
        oldDev.reseller_id, oldDev.first_seen_at || now, now, note.slice(0, 2000),
      ).run();
    } catch (_) {
      return { error: 'tombstone_failed', detail: String(e && e.message || e) };
    }
  }

  const moved = await moveOwnedMacRows(env, from, to, now);
  return {
    ok: true,
    old_mac: from,
    new_mac: to,
    device_id: oldDev.id,
    tombstone_id: tombId,
    moved,
  };
}
