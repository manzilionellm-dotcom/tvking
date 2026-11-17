// Tests du Worker novatube-downloads (aucun réseau : fetch simulé).
// node --test .github/novatube-tv/download-worker.test.mjs
import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest, TV_APK_URL, TV_SUMS_URL, MANIFEST_URL } from "./download-worker.mjs";

const HOST = "https://novatube.zuno8k.com";
const SHA = "dcb0ee51711d0785d67f471d68efc3b405addb4a229e5f5279ee3166177b03e4";
const MOBILE = {
  schemaVersion: 1, status: "verified", package: "com.sevenmotion.novatube",
  distribution: "private-apk",
  uploadCertificateSha256: "38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b",
  sourceCommit: "d024416f87ac7e2b083a88da1f72b65c78fb151a",
  releaseTag: "novatube-private-d024416f87ac7e2b083a88da1f72b65c78fb151a",
  url: "https://github.com/manzilionellm-dotcom/tvking/releases/download/novatube-private-d024416f87ac7e2b083a88da1f72b65c78fb151a/NOVATUBE-d024416f87ac7e2b083a88da1f72b65c78fb151a.apk",
  sha256: "a".repeat(64), versionName: "0.1.5", versionCode: 5, sizeBytes: 124177497,
};

function fakeFetch(map) {
  const seen = [];
  const fn = async (url) => {
    seen.push(String(url));
    const body = map[String(url)];
    if (body === undefined) return new Response("absent", { status: 404 });
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status: 200 });
  };
  fn.seen = seen;
  return fn;
}

test("/novatube.apk et ses alias → APK NovaTube TV fixe, sans aucune requête", async () => {
  for (const path of ["/novatube.apk", "/apk", "/", "/tv", "/tv.apk"]) {
    const f = fakeFetch({});
    const r = await handleRequest(new Request(HOST + path), f);
    assert.equal(r.status, 302, path);
    assert.equal(r.headers.get("Location"), TV_APK_URL, path);
    assert.equal(r.headers.get("Cache-Control"), "no-store");
    assert.equal(f.seen.length, 0, "la destination TV ne dépend d'aucune donnée externe");
  }
});

test("/version.json → métadonnées TV avec l'empreinte publiée", async () => {
  const r = await handleRequest(new Request(HOST + "/version.json"),
    fakeFetch({ [TV_SUMS_URL]: `${SHA}  NovaTube-TV.apk\n` }));
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.package, "com.sevenmotion.novatube.tv");
  assert.equal(body.sha256, SHA);
  assert.equal(body.url, TV_APK_URL);
});

test("/version.json : empreinte absente ou invalide → 503, jamais une autre app", async () => {
  assert.equal((await handleRequest(new Request(HOST + "/version.json"), fakeFetch({}))).status, 503);
  const bad = await handleRequest(new Request(HOST + "/version.json"),
    fakeFetch({ [TV_SUMS_URL]: "nimporte quoi" }));
  assert.equal(bad.status, 503);
});

test("NovaTube mobile conservé à l'identique sur /mobile.apk et /mobile/version.json", async () => {
  const f = fakeFetch({ [MANIFEST_URL]: MOBILE });
  const r = await handleRequest(new Request(HOST + "/mobile.apk"), f);
  assert.equal(r.status, 302);
  assert.equal(r.headers.get("Location"), MOBILE.url);
  const meta = await handleRequest(new Request(HOST + "/mobile/version.json"), f);
  assert.equal((await meta.json()).package, "com.sevenmotion.novatube");
});

test("mobile : manifeste d'une autre app ou d'un autre certificat → 503", async () => {
  const other = { ...MOBILE, package: "com.autre.app" };
  assert.equal((await handleRequest(new Request(HOST + "/mobile.apk"),
    fakeFetch({ [MANIFEST_URL]: other }))).status, 503);
  const cert = { ...MOBILE, uploadCertificateSha256: "b".repeat(64) };
  assert.equal((await handleRequest(new Request(HOST + "/mobile.apk"),
    fakeFetch({ [MANIFEST_URL]: cert }))).status, 503);
});

test("autres hôtes, chemins et méthodes refusés", async () => {
  assert.equal((await handleRequest(new Request("https://evil.example/novatube.apk"), fakeFetch({}))).status, 404);
  assert.equal((await handleRequest(new Request(HOST + "/autre.apk"), fakeFetch({}))).status, 404);
  assert.equal((await handleRequest(new Request(HOST + "/novatube.apk", { method: "POST" }), fakeFetch({}))).status, 405);
});
