// =========================================================
//  resume_start.dart — Où reprendre un film ou un épisode
// =========================================================
//  Même règle que la box : 5 secondes plus tôt pour retrouver le
//  fil, jamais avant 0. Moins de 30 secondes, on repart du début
//  (générique, mauvais choix). « Depuis le début » ignore la mémoire.
// =========================================================

class ResumeStart {
  const ResumeStart({required this.at, required this.resumes});

  final Duration at;
  final bool resumes;

  static const Duration rewind = Duration(seconds: 5);
  static const Duration minimum = Duration(seconds: 30);

  static ResumeStart decide({
    Duration? saved,
    bool fromStart = false,
  }) {
    if (fromStart || saved == null || saved < minimum) {
      return const ResumeStart(at: Duration.zero, resumes: false);
    }
    final int ms = saved.inMilliseconds - rewind.inMilliseconds;
    final Duration at = Duration(milliseconds: ms < 0 ? 0 : ms);
    return ResumeStart(at: at, resumes: at > Duration.zero);
  }
}
