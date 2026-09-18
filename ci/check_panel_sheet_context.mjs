#!/usr/bin/env node
// =========================================================
//  check_panel_sheet_context.mjs — « Détails » doit répondre
// =========================================================
//  CE QUE ÇA A COÛTÉ (18/09/2026).
//
//  Lionel : « Sur le panel admin le bouton Détails ne marche plus. »
//  Il ne marchait effectivement plus — et rien, nulle part, ne le
//  disait. Pas d'erreur rouge, pas de page blanche, pas une ligne dans
//  la console du navigateur. Un bouton qui s'enfonce, et rien derrière.
//
//  LA CAUSE, EN UNE PHRASE : `DevicesPage` appelait `useDeviceSheet()`
//  dans son propre corps, puis rendait `<AppLayout>` — qui contenait
//  `<DeviceSheetProvider>`. Le fournisseur était donc PLUS BAS que la
//  page dans l'arbre React, et un contexte ne remonte jamais vers ses
//  parents. La page lisait un contexte vide, `useDeviceSheet` rendait
//  sa version de repli « qui ne fait rien », et le clic partait dans le
//  néant.
//
//  CE QUI RENDAIT LA PANNE INVISIBLE : les MAC cliquables des AUTRES
//  pages continuaient d'ouvrir la fiche. Elles passent par `MacLink`,
//  un composant ENFANT, donc bien sous le fournisseur. Le panel avait
//  l'air en parfait état ; seule cette page-là était morte.
//
//  ---------------------------------------------------------
//  POURQUOI UN SCRIPT ET PAS « FAIRE ATTENTION »
//  ---------------------------------------------------------
//  Parce que rien ne l'attrape autrement. TypeScript est content : les
//  types sont justes des deux côtés. Le build Vite est vert. Le
//  déploiement est vert. C'est exactement le piège de la maison —
//  « vert ne veut pas dire livré », version arbre React.
//
//  Ce script relit le code source et refuse les trois façons connues
//  de re-créer la panne. Il tourne AVANT le build, dans les deux
//  workflows du panel (sanity check ET déploiement) : une seule
//  implémentation, deux appelants, comme ci/build_label.sh.
//
//  Usage :  node ci/check_panel_sheet_context.mjs [dossier-src]
//  Sortie :  0 = tout va bien   1 = une règle est violée (détaillée)
// =========================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const RACINE = process.argv[2] || 'admin-panel/src';

/// Le SEUL fichier autorisé à monter le fournisseur. Il est au-dessus
/// des routes : toutes les pages sont dessous par construction, y
/// compris celles qui rendent `AppLayout`.
const FICHIER_FOURNISSEUR = 'App.tsx';

/// Tous les `.ts`/`.tsx` sous [dir], chemins relatifs à [dir].
function fichiers(dir) {
  const out = [];
  for (const nom of readdirSync(dir)) {
    const chemin = join(dir, nom);
    if (statSync(chemin).isDirectory()) {
      out.push(...fichiers(chemin));
    } else if (/\.tsx?$/.test(nom)) {
      out.push(chemin);
    }
  }
  return out;
}

/// Le code DÉBARRASSÉ DE SES COMMENTAIRES.
///
///  Indispensable, et pas un détail : ce dépôt commente beaucoup (règle
///  n°1 de la maison), et les commentaires qui expliquent CE BUG-CI
///  citent forcément `<DeviceSheetProvider>` et `useDeviceSheet()`.
///  Sans ce nettoyage, le script s'accuse lui-même à travers la prose
///  qui le justifie — mesuré au premier essai : quatre faux positifs,
///  dont deux dans les commentaires que je venais d'écrire.
///
///  On retire les blocs `/* … */` (ce qui couvre aussi les commentaires
///  JSX `{/* … */}`) puis les LIGNES ENTIÈRES de commentaire. On ne
///  touche pas à un `//` en milieu de ligne : ce serait tronquer du
///  vrai code (une URL `https://…` en premier) et masquer un vrai
///  manquement. Tous les commentaires concernés ici sont en pleine
///  ligne.
function sansCommentaires(code) {
  return code
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => {
      const t = l.trim();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('///');
    })
    .join('\n');
}

const erreurs = [];
const listeFichiers = fichiers(RACINE);
const source = new Map(
  listeFichiers.map((f) => [f, sansCommentaires(readFileSync(f, 'utf8'))]),
);

/// MONTER le fournisseur (`<DeviceSheetProvider>`), à distinguer de le
/// DÉFINIR ou de l'importer — seul le montage place le contexte dans
/// l'arbre.
const monte = (code) => code.includes('<DeviceSheetProvider');

// ---------------------------------------------------------
//  RÈGLE 1 — le fournisseur est monté UNE fois, et dans App.tsx.
// ---------------------------------------------------------
//  Deux fournisseurs, ce serait deux fiches possibles à l'écran et
//  surtout deux vérités : celle que la page lit, et celle qui rend.
const monteurs = listeFichiers.filter((f) => monte(source.get(f)));

if (monteurs.length === 0) {
  erreurs.push(
    'Personne ne monte <DeviceSheetProvider>. Plus AUCUNE fiche '
    + 'appareil ne peut s\'ouvrir, sur aucune page.',
  );
} else if (monteurs.length > 1) {
  erreurs.push(
    'Le fournisseur est monté ' + monteurs.length + ' fois :\n'
    + monteurs.map((f) => '    • ' + relative('.', f)).join('\n')
    + '\n  Il n\'en faut QU\'UN, dans ' + FICHIER_FOURNISSEUR + '. Deux '
    + 'fournisseurs = deux contextes ; la page en lit un, la fiche est '
    + 'rendue par l\'autre, et le clic ne fait rien.',
  );
} else if (!monteurs[0].endsWith(FICHIER_FOURNISSEUR)) {
  erreurs.push(
    'Le fournisseur est monté dans ' + relative('.', monteurs[0]) + '.\n'
    + '  Sa place est ' + FICHIER_FOURNISSEUR + ', AU-DESSUS des routes. '
    + 'Plus bas, toute page qui appelle useDeviceSheet() dans son corps '
    + 'puis rend ce composant se retrouve HORS du contexte — c\'est '
    + 'exactement la panne du bouton « Détails » (18/09/2026).',
  );
}

// ---------------------------------------------------------
//  RÈGLE 2 — personne ne RE-monte le fournisseur dans un layout.
// ---------------------------------------------------------
//  C'est la rechute la plus tentante : « toutes les pages passent par
//  AppLayout, mettons-le là ». C'est précisément ce qui a cassé.
for (const f of listeFichiers) {
  const code = source.get(f);
  if (monte(code) && /\bexport function AppLayout\b/.test(code)) {
    erreurs.push(
      relative('.', f) + ' remonte <DeviceSheetProvider> dans AppLayout.\n'
      + '  Une page appelle useDeviceSheet() dans son corps PUIS rend '
      + '<AppLayout> : le fournisseur serait de nouveau plus bas qu\'elle, '
      + 'et son bouton « Détails » redeviendrait muet.',
    );
  }
}

// ---------------------------------------------------------
//  RÈGLE 3 — dans App.tsx, le fournisseur OUVRE avant les routes.
// ---------------------------------------------------------
//  Les règles 1 et 2 disent DANS QUEL FICHIER il vit. Celle-ci dit à
//  quelle HAUTEUR. Le glisser à l'intérieur d'une route le remettrait
//  sous les pages voisines — même panne, autre porte.
//
//  On prend `/devices` comme témoin : c'est la page qui est tombée, et
//  la seule à ouvrir la fiche depuis son propre corps.
//
//  CE QUE CETTE RÈGLE N'INTERDIT PAS, ET C'EST VOULU : qu'une page
//  rende `<AppLayout>` ET appelle `useDeviceSheet()`. C'est ce que fait
//  DevicesPage, et c'est parfaitement sain TANT QUE le fournisseur est
//  au-dessus des routes — ce que les trois règles garantissent
//  ensemble. L'interdire aurait obligé à réécrire la page pour un
//  danger que ces règles ferment déjà.
if (monteurs.length === 1 && monteurs[0].endsWith(FICHIER_FOURNISSEUR)) {
  const code = source.get(monteurs[0]);
  const ouverture = code.indexOf('<DeviceSheetProvider');
  const routeDevices = code.indexOf('path="/devices"');
  if (routeDevices >= 0 && ouverture > routeDevices) {
    erreurs.push(
      FICHIER_FOURNISSEUR + ' ouvre <DeviceSheetProvider> APRÈS la route '
      + '/devices.\n  Il doit envelopper TOUTE la table des routes. Plus '
      + 'bas, les pages ne sont plus dessous et leurs boutons '
      + '« Détails » redeviennent muets.',
    );
  }
}

// ---------------------------------------------------------
//  Verdict
// ---------------------------------------------------------
if (erreurs.length > 0) {
  console.error('❌ Fiche appareil : le contexte est mal branché.\n');
  for (const e of erreurs) console.error('  - ' + e + '\n');
  console.error(
    'Rappel de ce que ça coûte : le bouton « Détails » s\'enfonce et il '
    + 'ne se passe rien. Ni erreur, ni page blanche, ni trace console. '
    + 'Lionel a cherché de son côté avant de le signaler.',
  );
  process.exit(1);
}

//  On dit EXACTEMENT ce qu'on a vérifié, et rien de plus : un journal
//  qui affirme plus qu'il n'a mesuré est le défaut qui revient le plus
//  souvent dans ce dépôt.
console.log(
  '✅ Fiche appareil : un seul <DeviceSheetProvider>, dans '
  + FICHIER_FOURNISSEUR + ', ouvert avant la table des routes, et '
  + 'jamais remonté dans AppLayout (' + listeFichiers.length
  + ' fichiers relus).',
);
