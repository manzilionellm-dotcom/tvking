// Smoke test — BIBLIOTHÈQUE CINÉMA (VOD).
// Vérifie la brique PURE qui range les films par LANGUE (détection à partir du
// genre/titre — préfixes fournisseur type « FR - Action », « EN | Horror »,
// « VOSTFR », « AR | Drama »). Le reste (lecture réseau Xtream/M3U) n'est pas
// pur → couvert par les tests d'intégration, pas ici.
// Lancer : node cloudflare/vod_library.smoke.mjs
import assert from 'node:assert/strict';
import { detectVodLang } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- Français : FR / VF / VOSTFR / FRENCH / MULTI ---------------------------
assert.equal(detectVodLang('', 'FR - Action'), 'FR');
ok('« FR - Action » → FR');
assert.equal(detectVodLang('', 'FILMS VF'), 'FR');
ok('« FILMS VF » → FR');
assert.equal(detectVodLang('Le Parrain', 'VOSTFR | Classiques'), 'FR');
ok('« VOSTFR » → FR (sous-titré français)');
assert.equal(detectVodLang('', 'MULTI - Marvel'), 'FR');
ok('« MULTI » → FR (piste française incluse)');

// --- Anglais : EN / VO / ENGLISH --------------------------------------------
assert.equal(detectVodLang('', 'EN | Horror'), 'EN');
ok('« EN | Horror » → EN');
assert.equal(detectVodLang('', 'ENGLISH MOVIES'), 'EN');
ok('« ENGLISH MOVIES » → EN');

// --- Arabe / Espagnol -------------------------------------------------------
assert.equal(detectVodLang('', 'AR | Drama'), 'AR');
ok('« AR | Drama » → AR');
assert.equal(detectVodLang('', 'ES - Comedia'), 'ES');
ok('« ES - Comedia » → ES');

// --- Priorité + inconnu -----------------------------------------------------
// Le français est testé en premier (VOSTFR contient « FR ») : une catégorie
// « FR/EN » retombe sur FR, ce qui est le comportement voulu (piste FR dispo).
assert.equal(detectVodLang('', 'FR/EN Mix'), 'FR');
ok('« FR/EN » → FR (priorité au français quand présent)');
assert.equal(detectVodLang('Random Movie', 'Nouveautés'), '');
ok('genre neutre → langue inconnue (rangé dans « Autres »)');
assert.equal(detectVodLang(null, null), '');
ok('entrées nulles → langue vide (jamais d’erreur)');

console.log(`\n${n} assertions OK — bibliothèque cinéma (détection de langue) validée.`);
