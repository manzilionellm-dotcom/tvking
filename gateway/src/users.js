// =========================================================
//  users.js — Utilisateurs de la passerelle (papa + clones)
// =========================================================
//  Chaque utilisateur (papa, maman, enfants) a SES identifiants côté
//  passerelle, mais tous pointent vers la MÊME ligne fournisseur (une
//  seule « maison mère »). On peut ainsi :
//    • révoquer un clone sans casser les autres ;
//    • limiter le nombre de flux par utilisateur ;
//    • suivre/monitorer qui regarde quoi.
//
//  Le modèle brut (familles/users) est gardé en mémoire ET persisté dans
//  USERS_FILE pour permettre la gestion depuis le panel (CRUD).
// =========================================================
import { readFile, writeFile, rename } from 'node:fs/promises';
import { config } from './config.js';
import { log } from './logger.js';

// Modèle brut { families: [{ id, maxStreams, users: [{username,password,maxStreams}] }] }
let model = { families: [] };
// Index dérivés (reconstruits à chaque changement).
let byUsername = new Map();
let familyIndex = new Map();

function reindex() {
  const nextUsers = new Map();
  const nextFams = new Map();
  for (const fam of model.families || []) {
    const famId = String(fam.id || 'default');
    const famMax = Number.isFinite(fam.maxStreams) ? fam.maxStreams : config.providerMaxConnections;
    nextFams.set(famId, { id: famId, maxStreams: famMax });
    for (const u of fam.users || []) {
      if (!u.username || !u.password) continue;
      nextUsers.set(String(u.username), {
        username: String(u.username),
        password: String(u.password),
        familyId: famId,
        maxStreams: Number.isFinite(u.maxStreams) ? u.maxStreams : 1,
      });
    }
  }
  byUsername = nextUsers;
  familyIndex = nextFams;
}

export async function loadUsers(file = config.usersFile) {
  try {
    const raw = await readFile(file, 'utf8');
    const data = JSON.parse(raw);
    model = { families: Array.isArray(data.families) ? data.families : [] };
    reindex();
    log.info('users.loaded', { users: byUsername.size, families: familyIndex.size, file });
  } catch (e) {
    log.warn('users.load_failed', { file, error: String(e && e.message || e) });
  }
  return { users: byUsername.size, families: familyIndex.size };
}

// Écriture atomique (tmp + rename) pour ne jamais corrompre le fichier.
async function persist(file = config.usersFile) {
  const tmp = `${file}.tmp`;
  await writeFile(tmp, JSON.stringify(model, null, 2), 'utf8');
  await rename(tmp, file);
}

/** Vérifie un couple identifiant/mot de passe. Renvoie l'utilisateur ou null. */
export function authenticate(username, password) {
  const u = byUsername.get(String(username || ''));
  if (!u) return null;
  if (u.password !== String(password || '')) return null;
  return u;
}

export function getFamily(familyId) {
  return familyIndex.get(familyId) || null;
}

export function listUsers() {
  return [...byUsername.values()].map((u) => ({
    username: u.username, familyId: u.familyId, maxStreams: u.maxStreams,
  }));
}

// ---- CRUD (piloté par le panel via /admin/families) --------------------

export function listFamilies() {
  // On renvoie le modèle brut (identifiants inclus : le panel est admin et
  // l'opérateur a besoin des mots de passe pour les remettre au client).
  return (model.families || []).map((f) => ({
    id: String(f.id),
    maxStreams: Number.isFinite(f.maxStreams) ? f.maxStreams : config.providerMaxConnections,
    users: (f.users || []).map((u) => ({
      username: String(u.username),
      password: String(u.password),
      maxStreams: Number.isFinite(u.maxStreams) ? u.maxStreams : 1,
    })),
  }));
}

export async function createFamily({ id, maxStreams }) {
  const fid = String(id || '').trim();
  if (!fid) return { ok: false, code: 'bad_id' };
  if ((model.families || []).some((f) => String(f.id) === fid)) {
    return { ok: false, code: 'exists' };
  }
  const fam = {
    id: fid,
    maxStreams: Number.isFinite(maxStreams) ? Math.max(1, maxStreams) : config.providerMaxConnections,
    users: [],
  };
  model.families.push(fam);
  reindex();
  await persist();
  return { ok: true, family: fam };
}

export async function deleteFamily(id) {
  const fid = String(id);
  const before = model.families.length;
  model.families = model.families.filter((f) => String(f.id) !== fid);
  if (model.families.length === before) return { ok: false, code: 'not_found' };
  reindex();
  await persist();
  return { ok: true };
}

export async function addUser(familyId, { username, password, maxStreams }) {
  const fam = model.families.find((f) => String(f.id) === String(familyId));
  if (!fam) return { ok: false, code: 'family_not_found' };
  const uname = String(username || '').trim();
  const pass = String(password || '').trim();
  if (!uname || !pass) return { ok: false, code: 'bad_fields' };
  if (byUsername.has(uname)) return { ok: false, code: 'username_taken' };
  fam.users = fam.users || [];
  const u = { username: uname, password: pass, maxStreams: Number.isFinite(maxStreams) ? Math.max(1, maxStreams) : 1 };
  fam.users.push(u);
  reindex();
  await persist();
  return { ok: true, user: u };
}

export async function deleteUser(familyId, username) {
  const fam = model.families.find((f) => String(f.id) === String(familyId));
  if (!fam) return { ok: false, code: 'family_not_found' };
  const before = (fam.users || []).length;
  fam.users = (fam.users || []).filter((u) => String(u.username) !== String(username));
  if (fam.users.length === before) return { ok: false, code: 'not_found' };
  reindex();
  await persist();
  return { ok: true };
}
