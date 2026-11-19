// =========================================================
//  audio_report_dedupe.dart — Ne pas réécrire douze fois le même rapport
// =========================================================
//  Le lecteur natif envoie le rapport complet du son (12 lignes) à chaque
//  changement du compteur « Android en compte N ». Quand le son s'arrête et
//  repart, cela fait 12 lignes toutes les quelques secondes : le 15/11, presque
//  tout un journal collé n'était que ce rapport répété, et les lignes utiles
//  étaient noyées.
//
//  Règle : le PREMIER rapport d'une ouverture (même « zap n°N ») est écrit en
//  entier. Les suivants de la même ouverture ne gardent que les lignes qui ont
//  CHANGÉ. Un rapport identique n'écrit rien (la ligne « Annonces : … » qui
//  dit le changement part, elle, séparément).
//
//  La fiche rangée pour l'écran Diagnostic reste, elle, complète : seul le
//  journal est allégé. Objet pur : testé sans disque.
// =========================================================

class AudioReportDedupe {
  String? _zap;
  Set<String> _previous = <String>{};

  static final RegExp _rxCycle = RegExp(r'^Cycle : zap n°(\d+)');

  /// Lignes à écrire dans la boîte noire pour ce [body] (une par ligne non vide).
  List<String> linesFor(String body) {
    final List<String> lines = <String>[
      for (final String raw in body.split('\n'))
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    // Une ligne seule ou presque (« Zap : n°19. », « Seconde 3 : … ») n'est
    // pas un rapport : on la laisse passer telle quelle.
    if (lines.length <= 3) return lines;

    String? zap;
    for (final String line in lines) {
      final RegExpMatch? m = _rxCycle.firstMatch(line);
      if (m != null) {
        zap = m.group(1);
        break;
      }
    }
    final Set<String> now = lines.toSet();
    final bool sameOpening = zap != null && zap == _zap;
    final Set<String> before = _previous;
    _zap = zap;
    _previous = now;
    if (!sameOpening) return lines;
    return <String>[
      for (final String line in lines)
        if (!before.contains(line)) line,
    ];
  }

  /// Oublie le dernier rapport (tests, changement de profil).
  void reset() {
    _zap = null;
    _previous = <String>{};
  }
}
