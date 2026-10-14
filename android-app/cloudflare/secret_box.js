// =========================================================
//  secret_box.js — chiffrement au repos des secrets de source
// =========================================================
//  Protège le mot de passe Xtream et l'URL M3U (qui contient souvent
//  les identifiants dans la query) avant écriture D1.
//
//  Clé (dans cet ordre) :
//    - env.SOURCE_ENCRYPTION_KEY
//    - env.SECRETS_KEY   (nom historique du wrangler.toml)
//  Les deux se posent avec `wrangler secret put`, jamais dans le dépôt.
//  La clé est dérivée en AES-256 par SHA-256 (longueur libre, min. 16).
//
//  Format stocké : enc1.<iv b64url>.<ciphertext b64url>  (AES-GCM).
//  Sans clé, on laisse le texte tel quel pour ne pas casser une base
//  déjà en service : le chiffrement s'active dès que le secret est posé.
//  Une valeur déjà préfixée enc1. n'est jamais chiffrée une seconde fois.
//  Si le déchiffrement échoue, on renvoie null (pas le ciphertext).
// =========================================================

const PREFIX = 'enc1.';
const SECRET_FIELDS = ['password', 'm3u_url'];

function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/=+$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function b64urlDecode(s) {
  s = String(s).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

/// Chaîne de clé utilisable, ou '' si absente / trop courte.
export function encryptionKeyMaterial(env) {
  const raw = String(
    (env && (env.SOURCE_ENCRYPTION_KEY || env.SECRETS_KEY)) || '',
  ).trim();
  if (raw.length < 16) return '';
  return raw;
}

async function aesKey(env) {
  const raw = encryptionKeyMaterial(env);
  if (!raw) return null;
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(raw),
  );
  return crypto.subtle.importKey(
    'raw',
    digest,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
}

export async function sealField(env, value) {
  if (typeof value !== 'string' || !value) return value;
  if (value.startsWith(PREFIX)) return value;
  const key = await aesKey(env);
  if (!key) return value;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(value),
  ));
  return `${PREFIX}${b64url(iv)}.${b64url(ct)}`;
}

function b64stdDecode(s) {
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

/// Ancien format de la branche activation (`enc1:<iv b64>.<cipher b64>`).
/// On le lit encore pour ne pas perdre une ligne déjà chiffrée.
async function openLegacyColon(env, value) {
  const key = await aesKey(env);
  if (!key) return null;
  try {
    const rest = value.slice('enc1:'.length);
    const dot = rest.indexOf('.');
    if (dot < 1) return null;
    const iv = b64stdDecode(rest.slice(0, dot));
    const ct = b64stdDecode(rest.slice(dot + 1));
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      key,
      ct,
    );
    return new TextDecoder().decode(plain);
  } catch (_) {
    return null;
  }
}

export async function openField(env, value) {
  if (typeof value !== 'string' || !value) return value;
  if (value.startsWith('enc1:')) return openLegacyColon(env, value);
  if (!value.startsWith(PREFIX)) return value;
  const key = await aesKey(env);
  if (!key) return null;
  try {
    const rest = value.slice(PREFIX.length);
    const dot = rest.indexOf('.');
    if (dot < 1) return null;
    const iv = b64urlDecode(rest.slice(0, dot));
    const ct = b64urlDecode(rest.slice(dot + 1));
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      key,
      ct,
    );
    return new TextDecoder().decode(plain);
  } catch (_) {
    return null;
  }
}

export async function sealSource(env, source) {
  if (!source || typeof source !== 'object') return source;
  const out = { ...source };
  for (const field of SECRET_FIELDS) {
    if (typeof out[field] === 'string' && out[field]) {
      out[field] = await sealField(env, out[field]);
    }
  }
  return out;
}

export async function openSource(env, source) {
  if (!source || typeof source !== 'object') return source;
  const out = { ...source };
  for (const field of SECRET_FIELDS) {
    if (typeof out[field] === 'string' && out[field]) {
      out[field] = await openField(env, out[field]);
    }
  }
  return out;
}

export async function openSourceList(env, list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const item of list) out.push(await openSource(env, item));
  return out;
}
