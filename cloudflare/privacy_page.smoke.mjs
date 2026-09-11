// =========================================================
//  privacy_page.smoke.mjs — la page que Google va lire
// =========================================================
//  POURQUOI CE TEST EXISTE (11/09/2026).
//
//  La politique de confidentialité est la SEULE page de ce projet qu'un
//  examinateur humain de Google ouvre, lit en entier, et compare ligne à
//  ligne avec la fiche Play. Chacune de ses erreurs est un motif de
//  refus — et aucune ne se voit en regardant l'application tourner.
//
//  En une nuit, cette page a porté QUATRE défauts, tous découverts un
//  par un, à l'œil :
//
//    1. elle annonçait « Éditeur : The Kung (États-Unis) » — le nom d'un
//       PANNEAU IPTV FOURNISSEUR, pas celui du propriétaire ;
//    2. elle ne mentionnait pas com.sevenmotion.tv.seven_tv, l'app qui
//       part justement en revue ;
//    3. elle donnait deux adresses de contact différentes selon la
//       section, dont une qui ne figure pas au compte développeur ;
//    4. elle EMBARQUAIT DES NOTES INTERNES en commentaires HTML —
//       lisibles par « Afficher le code source » — qui parlaient de
//       « revendeur IPTV » et de « la défense de cette app devant
//       Google ». Exactement l'argument à ne pas tendre au relecteur.
//
//  Le quatrième est le plus instructif : une vérification avait été
//  faite, mais sur le texte AFFICHÉ, après suppression des commentaires.
//  Elle concluait « aucune fuite » alors que tout était lisible dans la
//  source. Un contrôle qui regarde au mauvais endroit est pire que pas
//  de contrôle : il rassure.
//
//  Ce fichier vérifie donc la CHAÎNE SERVIE, telle quelle, sans rien en
//  retirer au préalable.
// =========================================================
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('./worker.js', import.meta.url), 'utf8');

//  On extrait le littéral `PRIVACY_HTML` tel qu'il part sur le réseau.
const debut = src.indexOf('const PRIVACY_HTML');
if (debut < 0) throw new Error('PRIVACY_HTML introuvable dans worker.js');
const ouvrante = src.indexOf('`', debut);
const fermante = src.indexOf('`;', ouvrante + 1);
if (ouvrante < 0 || fermante < 0) throw new Error('littéral PRIVACY_HTML mal formé');
const page = src.slice(ouvrante + 1, fermante);

let ok = 0;
let ko = 0;
function verifie(condition, libelle) {
  if (condition) {
    ok += 1;
    console.log('  PASS', libelle);
  } else {
    ko += 1;
    console.log('  FAIL', libelle);
  }
}

console.log('\n1. Aucune note interne ne doit partir avec la page');
//  LE CONTRÔLE CENTRAL. On cherche dans la chaîne SERVIE, pas dans un
//  texte nettoyé — c'est toute la leçon du 11/09.
verifie(!page.includes('<!--'), 'zéro commentaire HTML dans la page servie');
//  On interdit les MOTS DE NOS NOTES, pas des mots du français courant.
//  « Google » a sa place ici : la page dit légitimement « Google TV ».
//  Un test qui l'interdirait serait faux, et un test faux finit par être
//  désactivé — après quoi il ne protège plus de rien.
for (const mot of [
  'thekung',
  'The Kung',
  'revendeur',
  'relecteur',
  'examinateur',
  'Play Console',
  'soumission',
]) {
  verifie(!page.includes(mot), `le mot « ${mot} » n'apparaît nulle part`);
}

console.log('\n2. Les trois applications Android sont nommées par leur PAQUET');
//  Un examinateur compare des noms de paquet, pas des noms commerciaux :
//  une app absente de sa propre politique se fait refuser.
for (const paquet of [
  'com.sevenmotion.tv.seven_tv',
  'com.manzilionellm.tvking',
  'com.manzilionellm.tvking.tv_king',
]) {
  verifie(page.includes(paquet), paquet);
}

console.log('\n3. L\'éditeur est celui de la fiche Play');
//  La règle Play sur les données utilisateur exige que l'entité nommée
//  dans la fiche Play figure dans la politique. C'est « 7 MOTION ».
verifie(page.includes('7 MOTION'), 'nom de la fiche Play présent');
verifie(
  page.includes('LIONEL MANZI SINDAYIHEBURA'),
  'nom légal du titulaire du compte présent',
);
verifie(!page.includes('The Few'), 'plus aucune trace de l\'ancien nom « The Few »');

console.log('\n4. Une seule adresse de contact, celle du compte développeur');
verifie(page.includes('support@7themotion.com'), 'support@7themotion.com présent');
verifie(!page.includes('contact@7themotion.com'), 'contact@7themotion.com absent');

console.log('\n5. Il n\'existe qu\'UNE politique dans tout le worker');
//  Une seconde page, figée au 10 juin, dormait dans ce fichier derrière
//  une route jamais atteinte. Elle aurait resurgi au premier
//  réordonnancement des routes, sans qu'aucun test ne bronche.
verifie(!src.includes('function privacyHtml'), 'pas de seconde page dormante');

console.log(`\n${ok} PASS, ${ko} FAIL`);
if (ko > 0) process.exit(1);
