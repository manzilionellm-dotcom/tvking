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
//  Format du fichier JSON (USERS_FILE) :
//  {
//    "families": [
//      { "id": "famille-karim", "maxStreams": 5,
//        "users": [
//          { "username": "papa",  "password": "xxxx", "maxStreams": 2 },
//          { "username": "maman", "password": "yyyy" },
//          { "username": "enfant1", "password": "zzzz" }
//        ] }
//    ]
//  }
// =========================================================
import { readFile } from 'node:fs/promises';
import { config } from './config.js';
import { log } from './logger.js';

/** @type {Map<string, {username:string,password:string,familyId:string,maxStreams:number}>} */
let byUsername = new Map();
/** @type {Map<string, {id:string,maxStreams:number}>} */
let families = new Map();

export async function loadUsers(file = config.usersFile) {
  const next = new Map();
  const fams = new Map();
  try {
    const raw = await readFile(file, 'utf8');
    const data = JSON.parse(raw);
    for (const fam of data.families || []) {
      const famId = String(fam.id || 'default');
      const famMax = Number.isFinite(fam.maxStreams) ? fam.maxStreams : config.providerMaxConnections;
      fams.set(famId, { id: famId, maxStreams: famMax });
      for (const u of fam.users || []) {
        if (!u.username || !u.password) continue;
        next.set(String(u.username), {
          username: String(u.username),
          password: String(u.password),
          familyId: famId,
          maxStreams: Number.isFinite(u.maxStreams) ? u.maxStreams : 1,
        });
      }
    }
    byUsername = next;
    families = fams;
    log.info('users.loaded', { users: byUsername.size, families: families.size, file });
  } catch (e) {
    // Pas de fichier / JSON invalide : on garde l'ancienne table si elle
    // existe, sinon table vide (toutes les auth échoueront proprement).
    log.warn('users.load_failed', { file, error: String(e && e.message || e) });
  }
  return { users: byUsername.size, families: families.size };
}

/** Vérifie un couple identifiant/mot de passe. Renvoie l'utilisateur ou null. */
export function authenticate(username, password) {
  const u = byUsername.get(String(username || ''));
  if (!u) return null;
  // Comparaison simple ; les mots de passe sont propres à la passerelle.
  if (u.password !== String(password || '')) return null;
  return u;
}

export function getFamily(familyId) {
  return families.get(familyId) || null;
}

export function listUsers() {
  return [...byUsername.values()].map((u) => ({
    username: u.username,
    familyId: u.familyId,
    maxStreams: u.maxStreams,
  }));
}
