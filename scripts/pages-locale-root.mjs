// ============================================================================
//  pages-locale-root.mjs — Langue automatique sur l'export statique GitHub Pages
// ----------------------------------------------------------------------------
//  Sur Vercel, proxy.ts choisit la langue côté serveur (adresse inchangée).
//  GitHub Pages n'a pas de serveur : après `next build` (export), ce script
//  écrit out/index.html et out/404.html qui lisent la langue du navigateur
//  (navigator.languages) et envoient le visiteur vers /tvking/<langue>/… .
//  Mêmes règles que app/i18n/config.ts (langue inconnue → anglais).
// ============================================================================
import { readFileSync, writeFileSync } from "node:fs";

const cfg = readFileSync("app/i18n/config.ts", "utf8");
const list = cfg.match(/export const LOCALES = \[([\s\S]*?)\] as const/)[1];
const LOCALES = [...list.matchAll(/"([a-z]{2})"/g)].map((m) => m[1]);
const BASE = "/tvking";

const script = `
(function () {
  var L = ${JSON.stringify(LOCALES)};
  var alias = { no: "nb", nn: "nb" };
  function pick() {
    var prefs = (navigator.languages && navigator.languages.length) ? navigator.languages : [navigator.language || ""];
    for (var i = 0; i < prefs.length; i++) {
      var t = String(prefs[i] || "").toLowerCase(), b = t.split(/[-_]/)[0];
      b = alias[b] || b;
      if (L.indexOf(b) >= 0) return b;
    }
    return prefs[0] ? "en" : "fr";
  }
  var base = "${BASE}";
  var rest = location.pathname.indexOf(base) === 0 ? location.pathname.slice(base.length) : location.pathname;
  var first = rest.split("/")[1];
  if (L.indexOf(first) >= 0) { document.getElementById("nf").style.display = "block"; return; }
  location.replace(base + "/" + pick() + (rest === "/" ? "/" : rest) + location.search + location.hash);
})();`;

const page = (title) => `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${title}</title>
<style>body{background:#121212;color:#ddd;font:16px system-ui;display:grid;place-items:center;min-height:100vh;margin:0}</style>
</head><body><p id="nf" style="display:none">404</p><script>${script}</script></body></html>`;

writeFileSync("out/index.html", page("TV King"));
writeFileSync("out/404.html", page("TV King"));
console.log(`✓ index.html + 404.html : ${LOCALES.length} langues`);
