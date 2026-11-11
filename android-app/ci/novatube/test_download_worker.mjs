import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { handleRequest, validateManifest } from "./download-worker.mjs";

const current = JSON.parse(await readFile(new URL("./latest-download.json", import.meta.url), "utf8"));
const request = (path = "/novatube.apk", method = "GET") => new Request(`https://novatube.zuno8k.com${path}`, { method });
const serve = (value) => async () => Response.json(value);

test("l'APK initial vérifié est servi sans cookie ni authentification", async () => {
  const response = await handleRequest(request(), serve(current));
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("Location"), current.url);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("la même adresse suit un nouveau manifeste sans redéployer le Worker", async () => {
  const sha = "a".repeat(40);
  const next = { ...current, sourceCommit: sha, sha256: "b".repeat(64), releaseTag: `novatube-private-${sha}`,
    url: `https://github.com/manzilionellm-dotcom/tvking/releases/download/novatube-private-${sha}/NOVATUBE-${sha}.apk` };
  assert.equal((await handleRequest(request(), serve(current))).headers.get("Location"), current.url);
  assert.equal((await handleRequest(request(), serve(next))).headers.get("Location"), next.url);
});

test("les métadonnées et HEAD décrivent le même fichier", async () => {
  const metadata = await handleRequest(request("/version.json"), serve(current));
  assert.deepEqual(await metadata.json(), current);
  const head = await handleRequest(request("/novatube.apk", "HEAD"), serve(current));
  assert.equal(head.headers.get("X-Novatube-SHA256"), current.sha256);
  assert.equal(await head.text(), "");
});

test("une autre application ou une clé différente ne peut pas être publiée", () => {
  for (const changes of [{ package: "com.manzilionellm.tvking" }, { uploadCertificateSha256: "0".repeat(64) },
    { status: "pending" }, { distribution: "play-aab" }, { sizeBytes: 0 }, { sourceCommit: "short" }]) {
    assert.throws(() => validateManifest({ ...current, ...changes }));
  }
});

test("une URL externe ou une release ZUNO est refusée", async () => {
  for (const url of ["https://example.com/NOVATUBE.apk", "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-mobile-cast-20261110-test/zuno-mobile.apk", current.url + "?redirect=other"]) {
    assert.equal((await handleRequest(request(), serve({ ...current, url }))).status, 503);
  }
});

test("une erreur réseau ou un JSON incomplet échoue sans redirection", async () => {
  for (const loader of [async () => { throw new Error("network"); }, async () => new Response("missing", { status: 404 }),
    async () => new Response("{"), serve({})]) {
    const response = await handleRequest(request(), loader);
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("Location"), null);
  }
});

test("le service n'écrit aucune donnée à la réception d'une requête", async () => {
  const never = async () => { throw new Error("must not fetch"); };
  assert.equal((await handleRequest(request("/novatube.apk", "POST"), never)).status, 405);
  assert.equal((await handleRequest(request("/mobile.apk"), never)).status, 404);
  assert.equal((await handleRequest(new Request("https://zuno8k.com/novatube.apk"), never)).status, 404);
});
