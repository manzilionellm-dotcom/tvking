// =========================================================
//  limits.js — Quotas de simultanéité (par utilisateur / par famille)
// =========================================================
//  Deux garde-fous DIFFÉRENTS et complémentaires :
//   1) Ici : combien de flux un même utilisateur / une même famille peut
//      regarder EN MÊME TEMPS (règle commerciale, ex. papa = 2 écrans).
//   2) Dans hub.js : combien de connexions DISTINCTES vers le fournisseur
//      sont ouvertes (jamais > PROVIDER_MAX_CONNECTIONS). Comme les flux
//      identiques sont mutualisés, rejoindre une chaîne déjà diffusée ne
//      consomme PAS de connexion fournisseur.
// =========================================================
import { getFamily } from './users.js';
import { config } from './config.js';

const activeByUser = new Map();
const activeByFamily = new Map();

function get(map, k) { return map.get(k) || 0; }

/**
 * Tente de réserver une session pour cet utilisateur.
 * @returns {{ ok: true, release: () => void } | { ok: false, code: string }}
 */
export function acquireSession(user) {
  const userActive = get(activeByUser, user.username);
  if (userActive >= (user.maxStreams || 1)) {
    return { ok: false, code: 'user_limit' };
  }
  const fam = getFamily(user.familyId);
  const famMax = fam ? fam.maxStreams : config.providerMaxConnections;
  const famActive = get(activeByFamily, user.familyId);
  if (famActive >= famMax) {
    return { ok: false, code: 'family_limit' };
  }
  activeByUser.set(user.username, userActive + 1);
  activeByFamily.set(user.familyId, famActive + 1);
  let released = false;
  return {
    ok: true,
    release() {
      if (released) return;
      released = true;
      activeByUser.set(user.username, Math.max(0, get(activeByUser, user.username) - 1));
      activeByFamily.set(user.familyId, Math.max(0, get(activeByFamily, user.familyId) - 1));
    },
  };
}

export function snapshotSessions() {
  return {
    byUser: Object.fromEntries(activeByUser),
    byFamily: Object.fromEntries(activeByFamily),
  };
}
