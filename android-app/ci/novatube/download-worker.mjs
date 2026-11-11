// Adresse publique stable. Le manifeste n'est remplacé qu'après la validation
// et la publication complète d'un APK signé NOVATUBE.
export const MANIFEST_URL = "https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/refs/heads/feature/novatube-play-aab/android-app/ci/novatube/latest-download.json";
const CERTIFICATE = "38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b";
const BOOTSTRAP_URL = "https://joe3v6of1vo5g2zl.public.blob.vercel-storage.com/novatube-0.1.5-5-26193f18.apk";
const HOST = "novatube.zuno8k.com";

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

export async function handleRequest(request, fetchManifest = fetch) {
  const url = new URL(request.url);
  const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
  if (url.hostname !== HOST || !["/", "/apk", "/novatube.apk", "/version.json"].includes(url.pathname)) {
    return new Response("Not found", { status: 404, headers });
  }
  if (!["GET", "HEAD"].includes(request.method)) {
    return new Response("Method not allowed", { status: 405, headers: { ...headers, Allow: "GET, HEAD" } });
  }
  try {
    const response = await fetchManifest(MANIFEST_URL, {
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
    if (url.pathname === "/version.json") {
      return new Response(request.method === "HEAD" ? null : JSON.stringify(manifest, null, 2) + "\n", {
        headers: { ...metadataHeaders, "Content-Type": "application/json; charset=utf-8" },
      });
    }
    return new Response(null, { status: 302, headers: { ...metadataHeaders, Location: manifest.url } });
  } catch {
    // Une panne de métadonnées ne doit jamais rediriger vers une autre app.
    return new Response(request.method === "HEAD" ? null : "Téléchargement NOVATUBE momentanément indisponible.", {
      status: 503, headers: { ...headers, "Retry-After": "30", "Content-Type": "text/plain; charset=utf-8" },
    });
  }
}

export default { fetch(request) { return handleRequest(request); } };
