// =========================================================
//  device_profiles.js — Profils famille, cote SERVEUR
// =========================================================
//  POURQUOI UN MODULE SEPARE (31/08/2026).
//
//  Ces fonctions etaient dans worker.js. Elles en sortent parce que DEUX
//  API doivent s'en servir :
//
//    • /api/v1/profiles/:mac  — ce que le VRAI panel (admin-panel, React,
//      tvking-admin.pages.dev) appelle, avec le jeton du revendeur ;
//    • /api/device-profiles/:mac — ce que l'APP interroge, sans jeton.
//
//  Les recopier aurait donne deux calculs de PIN a maintenir. Le jour ou
//  l'un des deux aurait derive d'une iteration, les codes poses depuis le
//  panel auraient cesse d'etre acceptes par les box — sans erreur nulle
//  part. Une seule implementation, importee des deux cotes.
//
//  Les helpers HTTP (json, badRequest) sont passes en PARAMETRE plutot
//  qu'importes : worker.js et api_v1.js ont chacun les leurs, avec leurs
//  propres en-tetes. Ce module ne connait que la logique metier.
// =========================================================

// =========================================================
//  PROFILS FAMILLE — pilotés depuis le panel
// =========================================================
//  Demande du propriétaire (30/08) : une seule source M3U collée dans le
//  panel, et le système génère CINQ profils indépendants — papa, maman,
//  trois enfants — chacun avec son PIN, sa liste de chaînes, son
//  historique, activable ou désactivable À DISTANCE, avec contrôle
//  parental par profil.
//
//  On suit EXACTEMENT le chemin déjà éprouvé de la source M3U :
//  une table D1 par MAC, une route publique que l'app interroge, des
//  routes d'admin protégées par le secret, et la poussée temps réel.
//  Inventer un second mécanisme aurait doublé la surface à maintenir.
//
//  ---------------------------------------------------------
//  LE PIN NE VOYAGE JAMAIS EN CLAIR
//  ---------------------------------------------------------
//  Le panel saisit « 1234 » ; on stocke et on envoie une EMPREINTE salée.
//  Si le code voyageait, il suffirait de lire la réponse HTTP (ou les
//  préférences de l'app) pour contourner le contrôle parental d'un
//  enfant. La formule est la même des deux côtés — HMAC-SHA256 itéré
//  20 000 fois — sinon aucun PIN ne serait jamais accepté.
export const PROFILE_PIN_ITERATIONS = 20000;

export async function profilePinHash(pin, salt) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(salt), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  let acc = enc.encode(`${salt}|${pin}`);
  for (let i = 0; i < PROFILE_PIN_ITERATIONS; i++) {
    acc = new Uint8Array(await crypto.subtle.sign('HMAC', key, acc));
  }
  // base64url AVEC son remplissage « = ». On ne remplace que « + » et
  // « / » : `base64Url.encode` de Dart garde le remplissage lui aussi, et
  // les deux écritures doivent être identiques AU CARACTÈRE PRÈS.
  //
  //  ⚠ Ce détail a été VÉRIFIÉ, pas supposé : les empreintes produites
  //  par CE code (exécuté sous Node) sont recopiées dans
  //  test/core/profiles/profile_pin_test.dart et comparées à celles de
  //  Dart. Un « = » de trop ou de moins ferait échouer TOUS les PIN, sans
  //  la moindre erreur dans les journaux — c'est exactement le genre de
  //  panne qu'on ne trouve pas en relisant le code.
  let bin = '';
  for (const b of acc) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_');
}

export function newProfileSalt() {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

//  LES CINQ PROFILS PAR DÉFAUT.
//
//  Générés automatiquement à la PREMIÈRE lecture d'une MAC qui n'en a
//  pas encore. L'admin n'a donc rien à créer : il colle sa source, et la
//  famille est là.
//
//  Choix assumés :
//   • aucun PIN au départ. Un PIN imposé que personne ne connaît
//     rendrait les profils inutilisables — l'admin les pose quand il
//     veut, depuis le panel ;
//   • les trois enfants naissent en mode ENFANT (adulte filtré). Le
//     défaut le plus sûr est celui qui protège ; un parent qui veut
//     l'inverse le décoche en un clic, alors que personne ne pense à
//     cocher une protection qu'il croit déjà active.
export const DEFAULT_FAMILY_PROFILES = [
  { id: 'papa',    name: 'Papa',     emoji: '👨', kids: false },
  { id: 'maman',   name: 'Maman',    emoji: '👩', kids: false },
  { id: 'enfant1', name: 'Enfant 1', emoji: '🧒', kids: true },
  { id: 'enfant2', name: 'Enfant 2', emoji: '👦', kids: true },
  { id: 'enfant3', name: 'Enfant 3', emoji: '👧', kids: true },
];

export function buildDefaultProfiles() {
  return DEFAULT_FAMILY_PROFILES.map((p) => ({
    id: p.id,
    name: p.name,
    emoji: p.emoji,
    enabled: true,
    kids: p.kids,
    pin: null,
    blockedCategories: [],
  }));
}

export async function ensureDeviceProfilesTable(env) {
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS device_profiles (
         mac TEXT PRIMARY KEY,
         profiles_json TEXT NOT NULL,
         updated_at INTEGER NOT NULL)`,
    ).run();
  } catch (_) { /* déjà créée */ }
}

//  NORMALISATION D'UN PROFIL VENU DU PANEL.
//
//  Le panel est du HTML : tout peut arriver. On borne, on coupe, on
//  refuse plutôt que de faire confiance. Un champ manquant prend une
//  valeur par défaut SÛRE — jamais une valeur qui ouvrirait un accès.
export function normalizeProfile(raw, index) {
  if (!raw || typeof raw !== 'object') return null;
  const id = String(raw.id || '').trim().toLowerCase()
    .replace(/[^a-z0-9_]/g, '').slice(0, 24);
  const name = String(raw.name || '').trim().slice(0, 24);
  if (!id || !name) return null;
  const cats = Array.isArray(raw.blockedCategories)
    ? raw.blockedCategories.map((c) => String(c).trim().slice(0, 64))
        .filter(Boolean).slice(0, 60)
    : [];
  return {
    id,
    name,
    emoji: String(raw.emoji || '👤').slice(0, 8),
    // `!== false` : un champ absent vaut ACTIVÉ. Un profil livré sans le
    // champ ne doit pas devenir inaccessible par accident.
    enabled: raw.enabled !== false,
    kids: raw.kids === true,
    // Le PIN n'est jamais relu du panel tel quel : il est soit déjà une
    // empreinte (on la garde), soit absent (pas de code).
    pin: (raw.pin && raw.pin.salt && raw.pin.hash)
      ? { salt: String(raw.pin.salt), hash: String(raw.pin.hash) }
      : null,
    blockedCategories: cats,
    _order: index,
  };
}

export async function readDeviceProfiles(env, MAC, { create = true } = {}) {
  if (!env.DB) return null;
  await ensureDeviceProfilesTable(env);
  let row;
  try {
    row = await env.DB
      .prepare('SELECT profiles_json FROM device_profiles WHERE mac = ?')
      .bind(MAC).first();
  } catch (_) { return null; }
  if (row && row.profiles_json) {
    try {
      const list = JSON.parse(row.profiles_json);
      if (Array.isArray(list) && list.length) {
        return list.map(normalizeProfile).filter(Boolean);
      }
    } catch (_) { /* JSON abîmé → on régénère plus bas */ }
  }
  if (!create) return null;
  //  GÉNÉRATION AUTOMATIQUE, à la première lecture.
  //  C'est ce qui réalise « un seul M3U collé, et cinq profils
  //  apparaissent » : l'admin n'a aucune étape supplémentaire à faire.
  const fresh = buildDefaultProfiles();
  try {
    await env.DB.prepare(
      `INSERT INTO device_profiles (mac, profiles_json, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(mac) DO UPDATE SET profiles_json = excluded.profiles_json,
                                      updated_at   = excluded.updated_at`,
    ).bind(MAC, JSON.stringify(fresh), Date.now()).run();
  } catch (_) { /* lecture seule : on renvoie quand même les défauts */ }
  return fresh;
}

export async function writeDeviceProfiles(env, MAC, list) {
  await ensureDeviceProfilesTable(env);
  await env.DB.prepare(
    `INSERT INTO device_profiles (mac, profiles_json, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(mac) DO UPDATE SET profiles_json = excluded.profiles_json,
                                    updated_at   = excluded.updated_at`,
  ).bind(MAC, JSON.stringify(list), Date.now()).run();
}
