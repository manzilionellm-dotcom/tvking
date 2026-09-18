// =========================================================
//  stream_proxy.js — le relais signé, en UN seul endroit
// =========================================================
//  À QUOI SERT LE RELAIS. Un flux IPTV arrive presque toujours en
//  HTTP simple, depuis un serveur qui n'est pas le nôtre. Un
//  navigateur en HTTPS refuse de le charger (contenu mixte), et le
//  fournisseur verrait l'IP de chaque spectateur. `/cast-proxy` sert
//  donc d'intermédiaire : même origine, HTTPS, CORS ouvert, re-typé
//  pour que mpegts.js le lise.
//
//  POURQUOI CE FICHIER EXISTE (18/09/2026). Ces trois fonctions
//  vivaient dans `worker.js`, où le récepteur Cast était leur unique
//  client. Le panneau « Téléphone » en a besoin à son tour, pour lire
//  une chaîne sans jamais faire voyager le mot de passe du
//  fournisseur jusqu'au navigateur.
//
//  Or `worker.js` importe `api_v1.js` : l'inverse ferait un cercle.
//  Et recopier la signature, ce serait le pire des deux mondes — le
//  jour où une copie change le format du jeton, l'autre refuse tout
//  ce que la première signe, sans que rien ne l'explique. Même raison
//  que `ci/build_label.sh` et `cloudflare/device_profiles.js` : une
//  seule implémentation, autant d'appelants qu'on veut.
//
//  RIEN N'A CHANGÉ DANS LEUR COMPORTEMENT. Ce sont les mêmes
//  fonctions, déplacées telles quelles — le format du jeton, la durée
//  de validité et la liste anti-SSRF sont identiques, sinon les liens
//  déjà signés cesseraient d'être acceptés.
// =========================================================

// HMAC-SHA256(secret, message) → hex. Web Crypto (dispo dans le runtime Worker).
export async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}


// Anti-SSRF : n'autorise que http(s) vers un hôte PUBLIC. Refuse localhost, les
// domaines *.local et les IP littérales privées / réservées (RFC1918, loopback,
// link-local, CGNAT, IPv6 ULA/loopback/link-local). Un hôte en nom de domaine
// est laissé passer (le runtime Worker ne route de toute façon pas vers les
// réseaux privés), mais une IP littérale privée est bloquée nettement.
export function isSafeUpstream(rawUrl) {
  let u;
  try { u = new URL(rawUrl); } catch (_) { return false; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
  let host = u.hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return false;
  // IPv6 littéral entre crochets → new URL garde les crochets dans hostname.
  if (host.startsWith('[')) host = host.slice(1, -1);
  // IPv4 littérale ?
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const o = m.slice(1).map((n) => parseInt(n, 10));
    if (o.some((n) => n > 255)) return false;
    const [a, b] = o;
    if (a === 10) return false;                       // 10.0.0.0/8
    if (a === 127) return false;                      // loopback
    if (a === 0) return false;                        // 0.0.0.0/8
    if (a === 169 && b === 254) return false;         // link-local
    if (a === 172 && b >= 16 && b <= 31) return false; // 172.16.0.0/12
    if (a === 192 && b === 168) return false;         // 192.168.0.0/16
    if (a === 100 && b >= 64 && b <= 127) return false; // CGNAT 100.64.0.0/10
    if (a >= 224) return false;                       // multicast / réservé
    return true;
  }
  // IPv6 littérale : bloque loopback (::1), ULA (fc00::/7), link-local (fe80::/10),
  // non-spécifié (::). Laisse passer le reste (adresses globales).
  if (host.includes(':')) {
    if (host === '::1' || host === '::') return false;
    if (host.startsWith('fc') || host.startsWith('fd')) return false;
    if (host.startsWith('fe8') || host.startsWith('fe9') ||
        host.startsWith('fea') || host.startsWith('feb')) return false;
    return true;
  }
  return true; // nom de domaine
}

/// Fabrique l'URL `/cast-proxy` SIGNÉE pour [u].
///
///  Le jeton est un HMAC de `url + "\n" + expiration`, tronqué à 32
///  caractères — et `/cast-proxy` le recalcule à l'identique pour
///  accepter ou refuser. C'est pour ça que ce format ne doit exister
///  qu'ICI : changé d'un côté seulement, plus rien ne joue.
///
///  Renvoie `null` si l'amont est refusé (schéma exotique, IP privée)
///  ou si aucun secret n'est configuré — l'appelant décide alors quoi
///  répondre, parce que « pas de secret » et « URL interdite » ne se
///  disent pas pareil à l'utilisateur.
export async function signProxyUrl(secret, origin, u, ttlSeconds = 12 * 3600) {
  if (!secret) return null;
  if (!u || !isSafeUpstream(u)) return null;
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const sig = (await hmacHex(secret, u + '\n' + exp)).slice(0, 32);
  const base = origin || 'https://app.7themotion.com';
  return {
    url: base + '/cast-proxy?u=' + encodeURIComponent(u) + '&e=' + exp + '&t=' + sig,
    expires_at: exp,
  };
}
