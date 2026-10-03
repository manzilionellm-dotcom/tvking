// Ancien coffre (préfixe enc1:). Le Worker et l'API utilisent
// secret_box.js (préfixe enc1., SOURCE_ENCRYPTION_KEY ou SECRETS_KEY).
// secret_box sait encore lire ce format pour ne pas perdre une ligne
// déjà écrite. Ne pas rebrancher ce module sur les écritures.
//
// Chiffrement au repos des secrets de source (mot de passe Xtream,
// URL M3U — elle contient souvent des identifiants dans la query).
// AES-GCM, clé dérivée de env.SECRETS_KEY (SHA-256). Jamais de clé en dur.
//
// Format : "enc1:<iv base64>.<cipher base64>".
// Une valeur sans préfixe reste en clair (lignes déjà en base, ou
// Worker sans SECRETS_KEY). On ne chiffre que si la clé est présente.

const PREFIX = 'enc1:';
const text = new TextEncoder();
const textDec = new TextDecoder();
const keyCache = new Map();

function b64(bytes) {
  let s = '';
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
  return btoa(s);
}

function b64dec(s) {
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

async function deriveKey(material) {
  const cached = keyCache.get(material);
  if (cached) return cached;
  const digest = await crypto.subtle.digest('SHA-256', text.encode(String(material)));
  const key = await crypto.subtle.importKey(
    'raw',
    digest,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
  keyCache.set(material, key);
  return key;
}

export async function sealText(plain, keyMaterial) {
  if (plain == null || plain === '') return plain;
  const value = String(plain);
  if (value.startsWith(PREFIX)) return value;
  if (!keyMaterial) return value;
  const key = await deriveKey(keyMaterial);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    text.encode(value),
  );
  return `${PREFIX}${b64(iv)}.${b64(cipher)}`;
}

export async function openText(stored, keyMaterial) {
  if (stored == null || stored === '') return stored;
  const value = String(stored);
  if (!value.startsWith(PREFIX)) return value;
  if (!keyMaterial) return null;
  const rest = value.slice(PREFIX.length);
  const dot = rest.indexOf('.');
  if (dot < 0) return null;
  try {
    const key = await deriveKey(keyMaterial);
    const iv = b64dec(rest.slice(0, dot));
    const cipher = b64dec(rest.slice(dot + 1));
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, cipher);
    return textDec.decode(plain);
  } catch (_) {
    return null;
  }
}

/// Chiffre password + m3u_url. Les autres champs (origin, id, username) restent lisibles.
export async function sealSource(source, keyMaterial) {
  if (!source || typeof source !== 'object') return source;
  const out = { ...source };
  if (out.password) out.password = await sealText(out.password, keyMaterial);
  if (out.m3u_url) out.m3u_url = await sealText(out.m3u_url, keyMaterial);
  return out;
}

export async function openSource(source, keyMaterial) {
  if (!source || typeof source !== 'object') return source;
  const out = { ...source };
  if (out.password) out.password = await openText(out.password, keyMaterial);
  if (out.m3u_url) out.m3u_url = await openText(out.m3u_url, keyMaterial);
  return out;
}
