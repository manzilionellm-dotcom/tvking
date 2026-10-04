// =========================================================
//  black_box_line.dart — Une ligne du journal : texte et politique de fsync
// =========================================================
//  Objet pur (aucun disque) : testé sans la boîte noire.
//
//  1. TEXTE. Même format qu'avant (« JJ/MM hh:mm:ss N [TAG] message »),
//     retours à la ligne aplatis. Nouveau : le message est EXPURGÉ à
//     l'écriture (mêmes règles que la copie envoyée au panel,
//     black_box_redaction.dart). Une exception Xtream ou M3U recopiait
//     l'adresse complète `player_api.php?username=…&password=…` dans le
//     journal local, lisible depuis Réglages → Boîte noire.
//
//  2. FSYNC. Avant, chaque ligne faisait `flushSync()` (un fsync disque)
//     sur le fil UI. Après un zap, le lecteur écrit 15 à 25 lignes [SON]
//     en quelques secondes : autant de fsync pendant que l'image démarre.
//     Un `write` seul suffit à survivre à une mort du processus (le noyau
//     garde la page) ; seul une coupure de courant perd ce qui n'est pas
//     synchronisé. On garde donc le fsync immédiat pour les lignes qui
//     précèdent une panne (avertissement, erreur, fatal) et on regroupe
//     les autres.
// =========================================================

import 'black_box_redaction.dart';

/// Niveau d'une ligne du journal.
enum BbLevel { info, warn, error, fatal }

/// Texte complet d'une ligne, retour à la ligne final compris.
String formatBlackBoxLine(
  DateTime t,
  BbLevel level,
  String tag,
  String message, {
  required bool redact,
}) {
  final String hh = t.hour.toString().padLeft(2, '0');
  final String mm = t.minute.toString().padLeft(2, '0');
  final String ss = t.second.toString().padLeft(2, '0');
  final String d =
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  final String lv = switch (level) {
    BbLevel.info => 'I',
    BbLevel.warn => 'W',
    BbLevel.error => 'E',
    BbLevel.fatal => 'F',
  };
  final String flat = message.replaceAll('\n', ' ');
  final String body = redact ? redactBlackBox(flat) : flat;
  return '$d $hh:$mm:$ss $lv [$tag] $body\n';
}

/// Vrai = cette ligne mérite un fsync tout de suite.
bool blackBoxFlushNow(BbLevel level, {required bool fsyncAll}) {
  if (fsyncAll) return true;
  return level != BbLevel.info;
}
