// =========================================================
//  panel_script.smoke.mjs — Le panel s'ouvre-t-il vraiment ?
// =========================================================
//  POURQUOI CE FICHIER EXISTE (31/08/2026).
//
//  Le panel d'administration est écrit dans un TEMPLATE LITERAL de
//  worker.js. Le JavaScript de la page vit donc à l'intérieur d'une
//  chaîne : `node --check cloudflare/worker.js` le voit comme du texte et
//  ne le lit jamais. Une erreur de syntaxe dedans passe donc TOUS les
//  contrôles, se déploie, et ne se voit que dans le navigateur.
//
//  Et elle ne se voit pas à moitié : une seule erreur de syntaxe empêche
//  le navigateur d'exécuter LE BLOC ENTIER. Le panel devient inerte —
//  y compris la connexion, donc sans même un écran où lire l'erreur.
//
//  LE CAS RÉEL. Ce jour-là, en ajoutant les profils famille, un
//  « \' » avait été écrit là où le template literal exige « \\' ». Dans
//  un template literal, « \' » vaut « ' » : la chaîne JavaScript se
//  fermait au milieu de l'attribut onclick. Le panel entier était mort,
//  et le commit était déjà poussé.
//
//  CE QUE CE TEST FAIT : il rend la page comme le worker la sert, en
//  extrait le <script>, et demande à Node de l'ANALYSER (sans l'exécuter
//  — il n'y a pas de navigateur ici). Puis il vérifie que chaque fonction
//  appelée depuis un attribut onclick/onkeydown existe bien : un onclick
//  qui pointe vers une fonction absente ne fait rien ET ne dit rien.
// =========================================================
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const src = readFileSync(new URL('./worker.js', import.meta.url), 'utf8');

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

// --- 1. Retrouver le template literal du panel, borne à borne. ---------
//  On avance caractère par caractère plutôt qu'avec une expression
//  régulière : le contenu est plein de backticks échappés et de « ${…} »,
//  qu'une regex confondrait avec la fin de la chaîne.
const start = src.indexOf('const ADMIN_PANEL_HTML = `');
if (start < 0) {
  console.log('  FAIL ADMIN_PANEL_HTML introuvable — le panel a été renommé ?');
  process.exit(1);
}
const open = src.indexOf('`', start);
let end = open + 1;
let depth = 0;
for (; end < src.length; end++) {
  if (src[end] === '\\') { end++; continue; }          // caractère échappé
  if (src[end] === '$' && src[end + 1] === '{') { depth++; end++; continue; }
  if (src[end] === '}' && depth) { depth--; continue; }
  if (src[end] === '`' && !depth) break;               // vraie fin
}

// --- 2. Rendre la page, exactement comme le worker la sert. -----------
const ctx = {};
vm.createContext(ctx);
try {
  vm.runInContext(
    src.slice(start, end + 1) + ';\nthis.__H = ADMIN_PANEL_HTML;', ctx,
  );
} catch (e) {
  console.log('  FAIL le template literal ne s\'évalue pas : ' + e.message);
  process.exit(1);
}
const html = ctx.__H;
ok(typeof html === 'string' && html.length > 5000,
  'la page se rend (' + (html ? html.length : 0) + ' caractères)');

// --- 3. Analyser chaque bloc <script>. --------------------------------
const blocs = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
ok(blocs.length > 0, 'la page contient au moins un bloc <script>');
blocs.forEach((code, n) => {
  let erreur = null;
  try {
    new vm.Script(code, { filename: 'panel-' + n + '.js' });
  } catch (e) {
    erreur = e.message;
  }
  ok(!erreur, 'bloc <script> n°' + n + ' (' + code.length + ' car.) analysé sans erreur'
    + (erreur ? ' — ' + erreur : ''));
});

// --- 4. Les onclick pointent-ils vers des fonctions qui existent ? ----
const tout = blocs.join('\n');
const declarees = new Set(
  [...tout.matchAll(/(?:async\s+)?function\s+([A-Za-z0-9_]+)\s*\(/g)].map((m) => m[1]),
);
const appelees = new Set(
  [...html.matchAll(
    /on(?:click|keydown|change|submit)="(?:event\.stopPropagation\(\);)?\s*(?:if\([^)]*\))?\s*([A-Za-z0-9_]+)\s*\(/g,
  )].map((m) => m[1]),
);
const manquantes = [...appelees].filter(
  (f) => !declarees.has(f) && !['return', 'if'].includes(f),
);
ok(manquantes.length === 0,
  'les ' + appelees.size + ' fonctions appelées par un attribut existent'
  + (manquantes.length ? ' — MANQUANTES : ' + manquantes.join(', ') : ''));

// --- 5. Le piège précis qui a mordu : « \' » au lieu de « \\' ». ------
//  Dans le SOURCE (pas la page rendue), un antislash simple devant une
//  apostrophe, à l'intérieur du template literal, est presque toujours
//  une erreur. On le signale même si l'analyse est passée : c'est le
//  genre de faute qui casse au premier changement d'à côté.
//  Les lignes de COMMENTAIRE sont ignorées : ce fichier-ci en contient
//  qui parlent justement de « \' », et un vérificateur qui se déclenche
//  sur sa propre explication finit par être désactivé.
const source = src.slice(start, end + 1);
const simples = source.split('\n')
  .map((l, i) => ({ l, n: i + 1 }))
  .filter(({ l }) => !/^\s*\/\//.test(l))
  .filter(({ l }) => /[^\\]\\'/.test(l) && !/\\\\'/.test(l));
ok(simples.length === 0,
  'aucun « \\\' » à antislash simple dans le panel'
  + (simples.length ? ' — ligne(s) ' + simples.map((x) => x.n).join(', ') : ''));

// --- 6. normalizeMac : ce que le revendeur tape doit être accepté. ----
//  L'application AFFICHE l'adresse SANS le « MK: » (DeviceIdentity.
//  stripPrefix côté Dart), mais le serveur l'EXIGE. Le client lit donc
//  sur sa télé une adresse qui, recopiée telle quelle dans le panel,
//  serait refusée. C'est la faute la plus probable de tout ce parcours —
//  et celle dont le message d'erreur n'aiderait personne.
//
//  On extrait la vraie fonction du panel et on la fait tourner.
{
  const m = /function normalizeMac\(raw\)\s*\{[\s\S]*?\n\}/.exec(tout);
  ok(!!m, 'normalizeMac est bien dans le panel');
  if (m) {
    const box = {};
    vm.createContext(box);
    vm.runInContext(m[0] + '\nthis.f = normalizeMac;', box);
    const f = box.f;
    const CANON = 'MK:AA:BB:CC:DD:EE';
    const cas = [
      ['MK:AA:BB:CC:DD:EE', CANON, 'la forme canonique'],
      ['AA:BB:CC:DD:EE', CANON, 'SANS le MK: — ce que le client lit sur sa télé'],
      ['aa:bb:cc:dd:ee', CANON, 'en minuscules'],
      ['AA-BB-CC-DD-EE', CANON, 'avec des tirets'],
      ['  MK:AA:BB:CC:DD:EE  ', CANON, 'copié-collé avec des espaces'],
      ['AABBCCDDEE', CANON, 'sans aucune ponctuation'],
      ['mk:aabbccddee', CANON, 'tout collé, en minuscules'],
      ['AA:BB:CC:DD', null, 'trop courte → refusée'],
      ['AA:BB:CC:DD:EE:FF', null, 'trop longue → refusée'],
      ['ZZ:BB:CC:DD:EE', null, 'caractères non hexadécimaux → refusée'],
      ['', null, 'vide → refusée'],
    ];
    for (const [entree, attendu, quoi] of cas) {
      ok(f(entree) === attendu, 'normalizeMac : ' + quoi);
    }
  }
}

console.log('\n' + pass + ' PASS, ' + fail + ' FAIL');
if (fail) process.exit(1);
