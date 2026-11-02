// Canaux clients déjà lus par les applications. Aucune URL provenant d'un
// appareil ou d'un bouton du panel ne peut changer l'autorité de publication.
const repository = 'manzilionellm-dotcom/tvking';
const channels = {
  tv: { tag: 'zuno-tv', apk: 'zuno-tv.apk', packageName: 'com.sevenmotion.tv.seven_tv' },
  // APK sideload historique ; prepare_play.py change uniquement l'AAB Play
  // vers com.manzilionellm.tvking. Les deux produits ne sont pas interchangeables.
  // La vraie recette mobile compile PHONE_UPDATE_TAG=phone-latest ; le
  // UpdateService reconstruit ensuite son URL depuis ce define. « latest »
  // dans le tronc partagé n'est pas le canal de cet APK préparé.
  mobile: { tag: 'phone-latest', apk: '7motion.apk', packageName: 'com.manzilionellm.tvking.tv_king' },
};
const ttl = 5 * 60_000;
const cache = new Map();
const flights = new Map();
const revisions = new Map();
const none = reason => ({ versionCode: 0, canForce: false, blockedReason: reason });

async function get(url, method = 'GET') {
  return fetch(url, { method, redirect: 'follow', signal: AbortSignal.timeout(5000),
    headers: { 'User-Agent': 'Zuno-Published-Update-Guard', Accept: 'application/vnd.github+json' } });
}

async function inspect(platform) {
  const channel = channels[platform];
  if (!channel) return none('unsupported_platform');
  const base = `https://github.com/${repository}/releases/download/${channel.tag}/`;
  try {
    const [releaseResponse, manifestResponse] = await Promise.all([
      get(`https://api.github.com/repos/${repository}/releases/tags/${channel.tag}`),
      get(`${base}version.json`),
    ]);
    if (!releaseResponse.ok || !manifestResponse.ok) return none('published_release_unavailable');
    const release = await releaseResponse.json();
    // Le workflow client Zuno utilise historiquement prerelease=true. Le tag
    // exact est l'autorité ; zuno-tv-test, phone-test et APK de revue exclus.
    if (release.tag_name !== channel.tag || release.draft !== false || !Array.isArray(release.assets)) {
      return none('published_release_invalid');
    }
    const manifestText = await manifestResponse.text();
    if (manifestText.length > 16_384) return none('published_manifest_invalid');
    const manifest = JSON.parse(manifestText);
    const url = `${base}${channel.apk}`;
    const sha = typeof manifest.sha256 === 'string' ? manifest.sha256.toLowerCase() : '';
    if (!Number.isSafeInteger(manifest.versionCode) || manifest.versionCode <= 0 ||
        manifest.versionCode > 2147483647 || !Number.isSafeInteger(manifest.size) || manifest.size <= 0 ||
        !/^[0-9a-f]{64}$/.test(sha) || manifest.url !== url ||
        (manifest.packageName != null && manifest.packageName !== channel.packageName) ||
        (manifest.package != null && manifest.package !== channel.packageName)) {
      return none('published_manifest_invalid');
    }
    const asset = release.assets.find(item => item.name === channel.apk);
    const manifestAsset = release.assets.find(item => item.name === 'version.json');
    if (!asset || asset.state !== 'uploaded' || asset.browser_download_url !== url ||
        asset.size !== manifest.size || asset.digest?.toLowerCase() !== `sha256:${sha}` ||
        !manifestAsset || manifestAsset.state !== 'uploaded' ||
        manifestAsset.browser_download_url !== `${base}version.json`) {
      return none('published_artifact_unverified');
    }
    // Le digest de l'asset GitHub vérifie aussi que ce manifeste est celui
    // publié dans la même release, pas une ancienne réponse de cache.
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(manifestText));
    const manifestSha = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    if (manifestAsset.digest?.toLowerCase() !== `sha256:${manifestSha}`) return none('published_manifest_unverified');
    const head = await get(url, 'HEAD');
    if (!head.ok || Number(head.headers.get('content-length')) !== manifest.size) {
      return none('published_artifact_unavailable');
    }
    return { versionCode: manifest.versionCode, canForce: true, blockedReason: '',
      url, sha256: sha, size: manifest.size };
  } catch { return none('published_release_unavailable'); }
}

export async function publishedRelease(platform, { fresh = false } = {}) {
  if (!channels[platform]) return none('unsupported_platform');
  const previous = cache.get(platform);
  if (!fresh && previous && previous.until > Date.now()) return previous.value;
  if (!fresh && flights.has(platform)) return flights.get(platform);
  const revision = (revisions.get(platform) || 0) + 1;
  revisions.set(platform, revision);
  const pending = inspect(platform).then(result => {
    const value = { ...result, checkedAt: Date.now(),
      source: `https://github.com/${repository}/releases/download/${channels[platform].tag}/version.json` };
    if (revisions.get(platform) === revision) cache.set(platform, { value, until: Date.now() + ttl });
    return value;
  }).finally(() => { if (flights.get(platform) === pending) flights.delete(platform); });
  flights.set(platform, pending);
  return pending;
}

// Les tests remplacent fetch ; aucun faux manifeste n'est embarqué en prod.
export function resetPublishedReleaseForTesting() { cache.clear(); flights.clear(); revisions.clear(); }
