// =========================================================
//  sound_report_parts.dart — accroche des autres angles
// =========================================================
//  Les 11 autres angles ajoutent des lignes à la fiche du lecteur.
//  Ces lignes remontent TOUTES SEULES dans le rapport complet
//  (elles sont dans le texte de la fiche, dédupliquées).
//  Pas besoin de toucher ce fichier pour ça.
//
//  Pour une phrase qui n'est PAS dans la fiche, chaque angle ajoute
//  UNE ligne dans [installSoundReportParts], et met son texte dans
//  SON fichier. Une ligne = un identifiant. Git fusionne des lignes
//  différentes sans les mélanger.
//
//  Exemple (mode d'emploi, ne pas décommenter) :
//
//    SoundReportExtensions.register(SoundReportExtension(
//      id: 'son-03-exemple',
//      lines: (SoundReportFacts faits) => <String>['Ma mesure : 12'],
//    ));
//
//  Le même id une deuxième fois REMPLACE la ligne. Il ne la double pas.
//  « chemin d'appel » ou « voies opposées » dans la phrase est lu par
//  le verdict. Une ligne « Spectre… » est seulement montrée.
// =========================================================

import 'sound_full_report.dart';

/// Appelé au début du rapport. Ajouter une ligne, pas un bloc.
void installSoundReportParts() {
  // son-11 : le verdict est déjà dans SoundFullReport. On ne pose pas
  // de phrase en plus. L'appel retire un id qui n'est pas utilisé, pour
  // que ce fichier référence vraiment le registre (sinon l'import
  // serait « inutilisé » et un angle ne saurait pas où écrire).
  SoundReportExtensions.unregister('son-11-rapport-unique');
}
