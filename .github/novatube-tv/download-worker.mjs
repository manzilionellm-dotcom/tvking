// =========================================================
//  novatube-downloads — adresse fixe NovaTube pour Downloader
// =========================================================
//  Demande du propriétaire (16/11/2026) : relier NovaTube TV à
//  https://novatube.zuno8k.com/novatube.apk (adresse tapée dans Downloader
//  sur la NVIDIA SHIELD).
//
//    /novatube.apk → MAXTUBE ; /apk, /, /tv et /tv.apk → NovaTube TV
//        Dernier APK de test VÉRIFIÉ par la CI NovaTube TV, copié dans la
//        pré-version fixe `novatube-tv-download` (nom stable NovaTube-TV.apk).
//    /version.json → MAXTUBE ; /tv/version.json → NovaTube TV
//
//    /mobile.apk, /mobile, /mobile/version.json → NovaTube MOBILE
//        Comportement historique conservé à l'identique (manifeste vérifié
//        de la branche NOVATUBE, certificat épinglé, destinations fixes).
//
//  Le Worker ne redirige JAMAIS ailleurs que vers ces deux destinations
//  du dépôt (ou le stockage historique du premier APK mobile).
// =========================================================

const HOST = "novatube.zuno8k.com";
const RELEASES = "https://github.com/manzilionellm-dotcom/tvking/releases/download";

// ---- NovaTube TV ----
export const TV_TAG = "novatube-tv-download";
export const TV_APK_URL = `${RELEASES}/${TV_TAG}/NovaTube-TV.apk`;
export const TV_SUMS_URL = `${RELEASES}/${TV_TAG}/SHA256SUMS.txt`;
const TV_PATHS = new Set(["/", "/apk", "/tv", "/tv.apk"]);

// Le code Downloader 4431009 conserve son adresse d’origine.
export const MAXTUBE_RELEASE = Object.freeze({
  schemaVersion: 1,
  app: "MAXTUBE",
  package: "com.sevenmotion.novatube.max",
  versionName: "1.0.1",
  versionCode: 2,
  sizeBytes: 60264699,
  sha256: "68dc23fba7e39ae6f58a411f677fd00b7434f288636efa0d5e1e778ba48da272",
  url: RELEASES + "/maxtube-v1.0.1-68dc23fb/MAXTUBE-1.0.1.apk",
});

// ---- NovaTube mobile (historique, inchangé) ----
export const MANIFEST_URL = "https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/refs/heads/feature/novatube-play-aab/android-app/ci/novatube/latest-download.json";
const CERTIFICATE = "38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b";
const BOOTSTRAP_URL = "https://joe3v6of1vo5g2zl.public.blob.vercel-storage.com/novatube-0.1.5-5-26193f18.apk";
const MOBILE_PATHS = new Set(["/mobile", "/mobile.apk"]);

export function validateManifest(value) {
  if (!value || value.schemaVersion !== 1 || value.status !== "verified" ||
      value.package !== "com.sevenmotion.novatube" ||
      value.distribution !== "private-apk" ||
      value.uploadCertificateSha256 !== CERTIFICATE ||
      !/^[0-9a-f]{40}$/.test(value.sourceCommit ?? "") ||
      !/^[0-9a-f]{64}$/.test(value.sha256 ?? "") ||
      !/^\d+\.\d+\.\d+$/.test(value.versionName ?? "") ||
      !Number.isSafeInteger(value.versionCode) || value.versionCode < 1 ||
      !Number.isSafeInteger(value.sizeBytes) || value.sizeBytes < 1) {
    throw new Error("Manifeste NOVATUBE invalide");
  }
  const url = new URL(value.url);
  const tag = `novatube-private-${value.sourceCommit}`;
  const releasePrefix = `/manzilionellm-dotcom/tvking/releases/download/${tag}/`;
  const githubAsset = url.hostname === "github.com" &&
    url.pathname.startsWith(releasePrefix) &&
    /^NOVATUBE-[0-9a-f]{40}\.apk$/.test(url.pathname.slice(releasePrefix.length)) &&
    url.pathname.slice(releasePrefix.length) === `NOVATUBE-${value.sourceCommit}.apk` &&
    value.releaseTag === tag;
  const bootstrap = url.href === BOOTSTRAP_URL && value.releaseTag === null &&
    value.sourceCommit === "26193f1889dd41d46f1e9f501eb750d906a71a05" &&
    value.sha256 === "c2172505f5cfede1c0c63fab5a2c83f0ce2dc1768681e3bc06b9bbfe26e97f00" &&
    value.sizeBytes === 124242223;
  if (url.protocol !== "https:" || url.username || url.password ||
      url.search || url.hash || url.port || (!githubAsset && !bootstrap)) {
    throw new Error("Destination de téléchargement non autorisée");
  }
  return value;
}

function unavailable(request, headers, what) {
  return new Response(request.method === "HEAD" ? null : `Téléchargement ${what} momentanément indisponible.`, {
    status: 503, headers: { ...headers, "Retry-After": "30", "Content-Type": "text/plain; charset=utf-8" },
  });
}

async function handleMobile(request, metadata, fetchImpl, headers) {
  try {
    const response = await fetchImpl(MANIFEST_URL, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(10000),
      cf: { cacheTtl: 30, cacheEverything: true },
    });
    if (!response.ok) throw new Error("Manifeste indisponible");
    const text = await response.text();
    if (text.length > 16384) throw new Error("Manifeste trop volumineux");
    const manifest = validateManifest(JSON.parse(text));
    const metadataHeaders = {
      ...headers,
      "X-Novatube-Commit": manifest.sourceCommit,
      "X-Novatube-SHA256": manifest.sha256,
    };
    if (metadata) {
      return new Response(request.method === "HEAD" ? null : JSON.stringify(manifest, null, 2) + "\n", {
        headers: { ...metadataHeaders, "Content-Type": "application/json; charset=utf-8" },
      });
    }
    return new Response(null, { status: 302, headers: { ...metadataHeaders, Location: manifest.url } });
  } catch {
    // Une panne de métadonnées ne doit jamais rediriger vers une autre app.
    return unavailable(request, headers, "NOVATUBE mobile");
  }
}

async function tvMetadata(request, fetchImpl, headers) {
  try {
    const response = await fetchImpl(TV_SUMS_URL, {
      redirect: "follow",
      signal: AbortSignal.timeout(10000),
      cf: { cacheTtl: 30, cacheEverything: true },
    });
    if (!response.ok) throw new Error("Empreinte indisponible");
    const text = await response.text();
    const match = /^([0-9a-f]{64})\s+\*?NovaTube-TV\.apk\s*$/m.exec(text.slice(0, 4096));
    if (!match) throw new Error("Empreinte invalide");
    const body = {
      schemaVersion: 1,
      app: "NovaTube TV",
      package: "com.sevenmotion.novatube.tv",
      channel: "test",
      url: TV_APK_URL,
      sha256: match[1],
    };
    return new Response(request.method === "HEAD" ? null : JSON.stringify(body, null, 2) + "\n", {
      headers: { ...headers, "Content-Type": "application/json; charset=utf-8", "X-Novatube-SHA256": match[1] },
    });
  } catch {
    return unavailable(request, headers, "NovaTube TV");
  }
}

export async function handleRequest(request, fetchImpl = fetch) {
  const url = new URL(request.url);
  const path = url.pathname;
  const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
  const known = TV_PATHS.has(path) || MOBILE_PATHS.has(path) ||
    path === "/novatube.apk" || path === "/version.json" ||
    path === "/tv/version.json" || path === "/mobile/version.json";
  if (url.hostname !== HOST || !known) {
    return new Response("Not found", { status: 404, headers });
  }
  if (!["GET", "HEAD"].includes(request.method)) {
    return new Response("Method not allowed", { status: 405, headers: { ...headers, Allow: "GET, HEAD" } });
  }
  if (MOBILE_PATHS.has(path)) return handleMobile(request, false, fetchImpl, headers);
  if (path === "/mobile/version.json") return handleMobile(request, true, fetchImpl, headers);
  if (path === "/tv/version.json") return tvMetadata(request, fetchImpl, headers);
  if (path === "/novatube.apk") {
    return new Response(null, { status: 302, headers: {
      ...headers, Location: MAXTUBE_RELEASE.url, "X-Novatube-SHA256": MAXTUBE_RELEASE.sha256,
    } });
  }
  if (path === "/version.json") {
    return new Response(request.method === "HEAD" ? null : JSON.stringify(MAXTUBE_RELEASE) + "\n", {
      headers: { ...headers, "Content-Type": "application/json; charset=utf-8",
        "X-Novatube-SHA256": MAXTUBE_RELEASE.sha256 },
    });
  }
  // NovaTube TV : destination FIXE (aucune donnée externe ne peut la changer).
  return new Response(null, { status: 302, headers: { ...headers, Location: TV_APK_URL } });
}

export default { fetch(request) { return handleRequest(request); } };
