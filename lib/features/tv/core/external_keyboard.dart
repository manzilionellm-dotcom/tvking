// =========================================================
//  external_keyboard.dart — taper avec AUTRE CHOSE que la grille
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (12/09/2026) :
//
//    « j'ai une télécommande sur mon téléphone, mais je ne parviens pas
//      à écrire avec le clavier — que ça se produise à la télé. »
//
//  ET IL A RAISON, C'ÉTAIT IMPOSSIBLE. L'écran de recherche de la box
//  n'avait AUCUN champ de saisie : la requête se construisait uniquement
//  en promenant le focus sur une grille de lettres. Rien, dans cet écran,
//  ne pouvait recevoir un caractère venu d'ailleurs. Une télécommande de
//  téléphone, un clavier Bluetooth, un clavier USB : tous tapaient dans
//  le vide, sans le moindre message.
//
//  ---------------------------------------------------------
//  DEUX CHEMINS D'ENTRÉE, ET ILS NE SE RESSEMBLENT PAS
//  ---------------------------------------------------------
//  1. LES ÉVÉNEMENTS DE TOUCHE. Un clavier Bluetooth/USB, et certaines
//     télécommandes, envoient des touches physiques. C'est ce fichier qui
//     décide lesquelles sont du TEXTE et lesquelles appartiennent à la
//     navigation — et cette frontière est tout le sujet : laisser passer
//     une flèche comme un caractère écrirait des symboles invisibles dans
//     la requête et casserait la navigation à la télécommande.
//
//  2. LE CLAVIER SYSTÈME (IME). L'application Télécommande de Google TV
//     n'envoie pas des touches : elle écrit dans le champ de saisie ACTIF
//     du téléviseur. Sans champ actif, elle n'a nulle part où écrire.
//     C'est le cas de la photo du propriétaire. Ce chemin-là se règle
//     dans l'écran (un vrai champ de saisie qu'on met au premier plan),
//     pas ici.
//
//  Ce fichier ne traite que le chemin 1, et il le traite PUREMENT : aucune
//  dépendance à un écran, donc testable sans téléviseur ni émulateur —
//  voir test/features/tv/external_keyboard_test.dart.
// =========================================================

import 'package:flutter/services.dart';

/// Touches qui pilotent l'interface et ne doivent JAMAIS devenir du texte.
///
/// La liste est volontairement large. Se tromper dans un sens écrit un
/// caractère parasite que le client verra et pourra effacer ; se tromper
/// dans l'autre AVALE une touche de navigation, et la télécommande cesse
/// de répondre — panne muette, impossible à comprendre depuis le canapé.
/// Dans le doute, on classe la touche comme navigation.
/// (`final` et non `const` : LogicalKeyboardKey redéfinit `==`, ce que Dart
/// interdit dans un ensemble constant. L'ensemble est construit une seule
/// fois au premier usage, ce qui revient au même à l'exécution.)
final Set<LogicalKeyboardKey> _touchesDeNavigation = <LogicalKeyboardKey>{
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.browserBack,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.contextMenu,
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
  // Touches média d'une télécommande : elles traversent l'écran de
  // recherche sans s'arrêter (le client peut couper le son en tapant).
  LogicalKeyboardKey.mediaPlay,
  LogicalKeyboardKey.mediaPause,
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaStop,
  LogicalKeyboardKey.mediaTrackNext,
  LogicalKeyboardKey.mediaTrackPrevious,
  LogicalKeyboardKey.audioVolumeUp,
  LogicalKeyboardKey.audioVolumeDown,
  LogicalKeyboardKey.audioVolumeMute,
  LogicalKeyboardKey.channelUp,
  LogicalKeyboardKey.channelDown,
  LogicalKeyboardKey.power,
};

/// Le caractère à AJOUTER à la requête, ou `null` si cette touche n'est
/// pas du texte.
///
/// [caractere] est ce que la plateforme a produit (`KeyEvent.character`) :
/// c'est LUI qui porte la disposition réelle du clavier et les accents.
/// On ne reconstruit jamais la lettre à partir du code de touche — un
/// clavier AZERTY, un clavier arabe ou une touche morte donneraient alors
/// n'importe quoi.
///
/// Refusé : les touches de navigation, les touches de contrôle (retour
/// arrière, tabulation, entrée arrivent parfois avec un « caractère » qui
/// est en réalité un code de contrôle), et tout ce qui est vide.
/// L'ESPACE, lui, est bien du texte : « canal plus ».
String? caractereTapable(LogicalKeyboardKey touche, String? caractere) {
  if (_touchesDeNavigation.contains(touche)) return null;
  if (caractere == null || caractere.isEmpty) return null;
  // Un caractère de contrôle (< 0x20) ou DEL (0x7F) n'est pas du texte.
  // L'espace vaut 0x20 : il passe, et c'est voulu.
  final int premier = caractere.codeUnitAt(0);
  if (premier < 0x20 || premier == 0x7F) return null;
  return caractere;
}

/// Cette touche efface-t-elle le dernier caractère ?
bool estRetourArriere(LogicalKeyboardKey touche) =>
    touche == LogicalKeyboardKey.backspace ||
    touche == LogicalKeyboardKey.delete;
