// =========================================================
//  black_box_upload_flag.dart — Interrupteur d'envoi
// =========================================================
//  Le journal peut partir au support (panel du revendeur).
//  Cet interrupteur, dans SharedPreferences, coupe l'envoi.
//  Coupé : rien ne quitte la box. Le journal local, lui,
//  continue d'être écrit (Réglages → Boîte noire).
//
//  Défaut : allumé, comme les autres fonctions en plus, pour
//  que le revendeur puisse aider sans demander au client de
//  chercher un réglage. Le texte de l'écran Boîte noire le
//  dit, et « En plus » permet de couper.
// =========================================================

import '../../features/box_extras/box_flag.dart';

/// Clé SharedPreferences. Une seule, lue à chaque envoi.
final BoxFlag blackBoxUploadFlag = BoxFlag('zuno.flag.blackbox_upload');
