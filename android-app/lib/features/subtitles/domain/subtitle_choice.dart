// =========================================================
//  subtitle_choice.dart — Pistes déjà dans le flux
// =========================================================
//  On ne traduit rien et on ne télécharge rien. On reconnaît
//  seulement la langue écrite sur la piste (fr, fra, fre…).
//  Une piste sans langue, ou « und », n'est PAS la langue de
//  la personne : on ne l'allume pas à sa place.
// =========================================================

import '../../cinema/domain/cinema_language.dart';

/// Une piste de sous-titres déjà proposée par le lecteur.
class SubtitleCue {
  const SubtitleCue({
    required this.group,
    required this.index,
    this.language,
    this.selected = false,
  });

  final int group;
  final int index;
  final String? language;
  final bool selected;
}

const Set<String> _kUndetermined = <String>{
  'und',
  'undetermined',
  'mul',
  'mis',
  'zxx',
  'xx',
};

/// Code langue utile, ou null si la piste n'en donne pas.
String? subtitleLanguage(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final String code = CinemaLanguage.normalizeCode(raw);
  if (code.isEmpty || _kUndetermined.contains(code)) return null;
  return code;
}

/// Pistes dans [userLanguage], dans l'ordre du flux.
/// Les autres langues restent dans le fichier : on ne les
/// propose pas comme « ta langue ».
List<SubtitleCue> tracksInLanguage(List<SubtitleCue> tracks, String userLanguage) {
  final String? want = subtitleLanguage(userLanguage);
  if (want == null) return const <SubtitleCue>[];
  return tracks
      .where((SubtitleCue t) => subtitleLanguage(t.language) == want)
      .toList(growable: false);
}

/// Quelle piste allumer toute seule.
///
///   • fonction coupée → null (on ne touche pas au lecteur)
///   • la personne a choisi « off » → null
///   • elle a choisi une langue → cette langue si le flux l'a,
///     sinon null (on n'en met pas une autre)
///   • aucun choix → la langue de l'application, si une piste
///     la porte
SubtitleCue? autoSubtitle({
  required List<SubtitleCue> tracks,
  required String userLanguage,
  required String? textPref,
  required bool enabled,
}) {
  if (!enabled) return null;
  if (textPref == 'off') return null;
  final String? wanted = (textPref != null && textPref.trim().isNotEmpty)
      ? subtitleLanguage(textPref)
      : subtitleLanguage(userLanguage);
  if (wanted == null) return null;
  for (final SubtitleCue track in tracks) {
    if (subtitleLanguage(track.language) == wanted) return track;
  }
  return null;
}

/// Cycle : éteint (-1) → 1re piste de la langue → suivante → éteint.
/// [currentIndex] vaut -1 quand rien n'est allumé.
int nextSubtitleStep(int currentIndex, int count) {
  if (count <= 0) return -1;
  if (currentIndex < 0 || currentIndex >= count) return 0;
  if (currentIndex == count - 1) return -1;
  return currentIndex + 1;
}
