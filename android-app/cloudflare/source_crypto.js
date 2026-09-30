// =========================================================
//  source_crypto.js — Chiffrement au repos des mots de passe IPTV
// =========================================================
//  Les codes Xtream et les liens M3U (qui contiennent souvent le mot
//  de passe dans l'adresse) sont chiffrés AVANT d'être écrits dans D1.
//  La clé vient UNIQUEMENT de la variable Cloudflare
//  `SOURCE_ENCRYPTION_KEY` (wrangler secret). Elle n'est jamais écrite
//  dans le dépôt.
//
//  Compatibilité :
//    - pas de clé configurée → on laisse le texte en clair (les box
//      déjà servies continuent de marcher). On n'invente PAS une clé
//      de secours dans le code ;
//    - une ligne déjà en clair (sans préfixe) reste lisible ;
//    - une ligne `enc1:` est déchiffrée pour l'app et le panel. Si la
//      clé manque, on renvoie un mot de passe vide plutôt que le
//      chiffré (qui ne servirait à rien et fuirait dans les journaux).
// =========================================================

const PREFIX = 'enc1:';

function bytesToB64(bytes) {
  let s = '';
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
  return btoa(s);
}

function b64ToBytes(s) {
  const raw = atob(s);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function keyMaterial(key) {
  if (typeof key !== 'string') return '';
  return key.trim();
}

async function aesKey(material) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(material),
  );
  return crypto.subtle.importKey(
    'raw',
    digest,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
}

/// Chiffre une chaîne. `null` / vide / déjà chiffrée : renvoyés tels quels.
export async function sealString(plain, key) {
  if (plain == null || plain === '') return plain;
  const text = String(plain);
  if (text.startsWith(PREFIX)) return text;
  const material = keyMaterial(key);
  if (!material) return text;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    await aesKey(material),
    new TextEncoder().encode(text),
  ));
  return `${PREFIX}${bytesToB64(iv)}:${bytesToB64(ct)}`;
}

/// Déchiffre une chaîne. Le clair historique (sans préfixe) passe.
/// Chiffré illisible (clé absente ou corrompue) → `null`.
export async function openString(stored, key) {
  if (stored == null || stored === '') return stored;
  const text = String(stored);
  if (!text.startsWith(PREFIX)) return text;
  const material = keyMaterial(key);
  if (!material) return null;
  const body = text.slice(PREFIX.length);
  const colon = body.indexOf(':');
  if (colon <= 0) return null;
  try {
    const iv = b64ToBytes(body.slice(0, colon));
    const ct = b64ToBytes(body.slice(colon + 1));
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      await aesKey(material),
      ct,
    );
    return new TextDecoder().decode(plain);
  } catch (_) {
    return null;
  }
}

/// Chiffre les champs sensibles d'une source (mot de passe + lien M3U).
export async function sealSource(source, key) {
  if (!source || typeof source !== 'object') return source;
  const next = { ...source };
  if (next.password != null) next.password = await sealString(next.password, key);
  if (next.m3u_url != null) next.m3u_url = await sealString(next.m3u_url, key);
  return next;
}

/// Déchiffre les champs sensibles. Le reste de l'objet ne bouge pas.
export async function openSource(source, key) {
  if (!source || typeof source !== 'object') return source;
  const next = { ...source };
  if (next.password != null) next.password = await openString(next.password, key);
  if (next.m3u_url != null) next.m3u_url = await openString(next.m3u_url, key);
  return next;
}

export function encryptionKey(env) {
  return keyMaterial(env && env.SOURCE_ENCRYPTION_KEY);
}

/// Retire d'une URL ce qui sert de secret : userinfo (`user:pass@`)
/// et paramètres username / password / token / pass. L'hôte reste,
/// pour le diagnostic, sans livrer le code.
export function redactCredentialUrl(raw) {
  const text = String(raw || '').trim();
  if (!text) return '';
  try {
    const u = new URL(text);
    u.username = '';
    u.password = '';
    for (const name of ['username', 'password', 'pass', 'token', 'pwd']) {
      if (u.searchParams.has(name)) u.searchParams.set(name, '');
    }
    return u.toString();
  } catch (_) {
    return text
      .replace(/\/\/[^/@\s]+@/g, '//')
      .replace(/([?&](?:username|password|pass|token|pwd)=)[^&]*/gi, '$1');
  }
}
