// =========================================================
//  vod_taste.dart — « Goût » du client : score de compatibilité + tirage
// =========================================================
//  Deux touches premium, 100 % locales (à partir de l'historique du client,
//  aucun profilage distant) :
//
//   • SCORE DE COMPATIBILITÉ (« 94 % pour vous ») : à partir des catégories
//     que le client REGARDE (derniers vus + Ma Liste), on estime à quel
//     point un film lui correspond. On mélange l'affinité de catégorie et
//     la note de la source (si dispo). Volontairement HONNÊTE : sans
//     historique, aucun score n'est affiché (pas de faux « 97 % »).
//
//   • TIRAGE « SURPRENDS-MOI » : choisit UN film à lancer tout de suite,
//     en favorisant les catégories préférées — mais avec une part
//     d'aléa (index fourni par l'appelant → pur & testable, pas de
//     Random caché) pour ne pas reproposer toujours le même.
// =========================================================
import '../domain/vod_movie.dart';

abstract final class VodTaste {
  /// Poids par catégorie (minuscule) construit depuis l'historique. Les
  /// « derniers vus » pèsent plus que « Ma Liste » (intention réelle vs
  /// envie). Renvoie une map vide si aucun historique.
  static Map<String, double> affinity({
    required List<VodMovie> recent,
    required List<VodMovie> watchlist,
  }) {
    final Map<String, double> w = <String, double>{};
    for (final VodMovie m in recent) {
      final String c = m.category.trim().toLowerCase();
      if (c.isEmpty) continue;
      w[c] = (w[c] ?? 0) + 2.0;
    }
    for (final VodMovie m in watchlist) {
      final String c = m.category.trim().toLowerCase();
      if (c.isEmpty) continue;
      w[c] = (w[c] ?? 0) + 1.0;
    }
    return w;
  }

  /// Score 0..100 pour [movie] selon l'affinité de catégorie + la note de
  /// la source. Renvoie null si on ne peut rien dire d'honnête (pas
  /// d'affinité connue pour cette catégorie ET pas de note). Le score est
  /// borné à [72..98] quand il est affiché : jamais 100 % (rien n'est
  /// parfait), jamais en dessous de 72 (on n'affiche PAS un mauvais score,
  /// on n'affiche RIEN — cf. le null plus haut).
  static int? matchPercent(
    VodMovie movie, {
    required Map<String, double> affinity,
    double maxAffinity = 0,
  }) {
    final String c = movie.category.trim().toLowerCase();
    final double aff = affinity[c] ?? 0;
    final double? rating = _rating10(movie.rating);
    // Rien d'honnête à dire : catégorie inconnue du goût ET pas de note.
    if (aff <= 0 && rating == null) return null;

    // Composante AFFINITÉ (0..1) : la catégorie du film rapportée à la
    // catégorie la plus regardée.
    final double affNorm =
        maxAffinity > 0 ? (aff / maxAffinity).clamp(0.0, 1.0) : 0.0;
    // Composante NOTE (0..1) : note/10 si dispo, sinon neutre 0,6.
    final double rateNorm = rating != null ? (rating / 10.0) : 0.6;

    // 65 % affinité, 35 % note → un contenu de ta catégorie fétiche et
    // bien noté frôle 98 %.
    final double s = 0.65 * affNorm + 0.35 * rateNorm;
    final int pct = (72 + (s * 26)).round().clamp(72, 98);
    return pct;
  }

  /// « Surprends-moi » : index (dans [movies]) du film à lancer, pondéré par
  /// l'affinité de catégorie. [rngUnit] est un aléa 0..1 fourni par
  /// l'appelant (→ pur, testable). Renvoie -1 si la liste est vide.
  static int surpriseIndex(
    List<VodMovie> movies, {
    required Map<String, double> affinity,
    required double rngUnit,
  }) {
    if (movies.isEmpty) return -1;
    // Poids par film : 1 (base) + affinité de sa catégorie. Tout le monde a
    // une chance ; les catégories aimées en ont plus.
    final List<double> weights = <double>[
      for (final VodMovie m in movies)
        1.0 + (affinity[m.category.trim().toLowerCase()] ?? 0),
    ];
    final double total = weights.fold(0.0, (double a, double b) => a + b);
    if (total <= 0) return 0;
    double target = (rngUnit.clamp(0.0, 0.999999)) * total;
    for (int i = 0; i < weights.length; i++) {
      target -= weights[i];
      if (target < 0) return i;
    }
    return movies.length - 1;
  }

  /// Note de la source ramenée sur 10 (« 8.2 », « 4.1 » sur 5 → 8.2…).
  /// Best-effort : parse tolérant, null si illisible.
  static double? _rating10(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final double? v = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    // Certaines sources notent sur 5 → on remet sur 10.
    return v <= 5.0 ? v * 2.0 : v.clamp(0.0, 10.0);
  }
}
