// =========================================================
//  audio_attribute_trial.dart — Essai film / musique / parole
// =========================================================
//  Le lecteur natif décide des chiffres (AudioProfile.kt). Ici on ne
//  fait que le bouton : l'ordre des mots, et le libellé. « off » est
//  le défaut. Un mot inconnu retombe sur « off » : on ne change pas
//  le son parce qu'une préférence est illisible.
//
//  Aucune adresse, aucun secret. Pas de Flutter : le test unitaire
//  peut tourner sans écran.
// =========================================================

class AudioAttributeTrial {
  AudioAttributeTrial._();

  static const String key = 'zuno.audio.profile';

  static const String off = 'off';
  static const String film = 'film';
  static const String music = 'musique';
  static const String speech = 'parole';
  static const String media3 = 'media3';

  /// Même ordre que AudioProfile.ORDER. Le premier est le défaut.
  static const List<String> order = <String>[off, film, music, speech, media3];

  static String parse(String? raw) {
    if (raw == null) return off;
    for (final String wire in order) {
      if (wire == raw) return wire;
    }
    return off;
  }

  static String next(String? raw) {
    final String cur = parse(raw);
    final int i = order.indexOf(cur);
    return order[(i + 1) % order.length];
  }

  /// Libellé du bouton. « coupé » = le son d'aujourd'hui.
  static String label(String? raw) {
    switch (parse(raw)) {
      case film:
        return 'Attributs : film';
      case music:
        return 'Attributs : musique';
      case speech:
        return 'Attributs : parole';
      case media3:
        return 'Attributs : défaut Media3';
      default:
        return 'Attributs : coupé';
    }
  }

  /// Vrai seulement quand un essai est armé. Coupé = bouton au repos.
  static bool armed(String? raw) => parse(raw) != off;
}
