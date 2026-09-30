// =========================================================
//  device_guard.js — Décisions d'accès (sans base de données)
// =========================================================
//  Le code affiché sur la télé (la MAC) ne doit plus suffire à lire
//  ou à remplacer les codes IPTV. Ces fonctions disent OUI ou NON ;
//  le Worker, lui, parle à D1.
//
//  Deux époques, pour ne pas couper les box déjà installées :
//    1. La box a enregistré un secret à elle (`enrolled`) → sans ce
//       secret, on ne donne RIEN (ni lecture, ni écriture).
//    2. La box n'a pas encore le nouveau logiciel → on peut encore
//       LIRE la source si la licence est lisible et jouable. On ne
//       donne plus les codes quand la base tousse (avant, une panne
//       ouvrait le verrou). La sauvegarde cloud, elle, est fermée
//       tout de suite : un inconnu ne peut plus l'écraser.
// =========================================================

/// Comparaison en temps constant. Longueurs différentes → refus.
export function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export async function hashDeviceSecret(secret) {
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(String(secret)),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/// Le secret présenté correspond-il à l'empreinte stockée ?
export async function secretMatches(presented, storedHash) {
  if (!presented || !storedHash) return false;
  const got = await hashDeviceSecret(presented);
  return safeEqual(got, String(storedHash));
}

/// Licence jouable ? `status` vient de d1StatusForMac. null = box
/// inconnue ou lecture avalée : on ne livre pas. `readFailed` = la
/// lecture a planté. Sans base, on ne livre pas les codes.
export function legacyCredentialsAllowed({ hasDb, readFailed, status }) {
  if (!hasDb || readFailed || !status) return false;
  if (status.expired || status.frozen || status.banned) return false;
  return true;
}

/// Lecture device-source / config.
///   deny  → ne pas mettre de mot de passe dans la réponse
///   legacy → box pas encore enrôlée, licence OK
///   ok → secret valide, la licence sera revérifiée par l'appelant
export function deviceReadDecision({ enrolled, secretOk, legacyOk }) {
  if (enrolled) {
    if (!secretOk) return 'deny';
    return legacyOk ? 'ok' : 'blocked';
  }
  return legacyOk ? 'legacy' : 'blocked';
}

/// Sauvegarde cloud : toujours un secret déjà enregistré ET présenté.
export function backupAllowed({ enrolled, secretOk }) {
  return !!(enrolled && secretOk);
}

/// Enrôlement / rotation.
///   create  → première fois (ou android id pas encore connu)
///   rotate  → réinstallation : l'android id déjà vu correspond
///   idempotent → le même secret se représente
///   deny → quelqu'un qui n'a que la MAC
export function enrollDecision({
  hasSecret,
  presentedMatches,
  knownAndroidId,
  presentedAndroidId,
}) {
  const known = String(knownAndroidId || '').trim();
  const presented = String(presentedAndroidId || '').trim();
  if (hasSecret && presentedMatches) return 'idempotent';
  if (known && presented && known === presented) {
    return hasSecret ? 'rotate' : 'create';
  }
  if (!hasSecret && !known) return 'create';
  return 'deny';
}

/// Un secret d'appareil acceptable : assez long, pas une MAC recopiée.
export function acceptableDeviceSecret(secret) {
  if (typeof secret !== 'string') return false;
  const s = secret.trim();
  if (s.length < 32 || s.length > 200) return false;
  if (/^MK(?::[0-9A-F]{2}){5}$/i.test(s)) return false;
  return true;
}
