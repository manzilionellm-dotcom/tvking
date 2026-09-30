// =========================================================
//  profile_policies.dart — Règles simples, testables
// =========================================================
//  Trois questions que l'écran ne doit pas réinventer :
//    1. Faut-il montrer le choix de profil au démarrage ?
//    2. Le mode enfants est-il forcé ? Peut-on le couper ?
//    3. Cette chaîne est-elle à cacher dans la recherche
//       enfant, SANS bloquer une chaîne normale ?
// =========================================================

abstract final class StartupProfilePolicy {
  /// On ne montre le choix que s'il y a vraiment un choix
  /// (au moins 2 profils) ET que la maison ne l'a pas coupé.
  ///
  /// Un seul profil, ou l'option désactivée : l'accueil
  /// s'ouvre tout de suite. Aucun écran ne se met devant
  /// les chaînes.
  static bool shouldOffer({
    required bool? askOnStartup,
    required int profileCount,
  }) {
    if (profileCount < 2) return false;
    if (askOnStartup == false) return false;
    return true;
  }
}

abstract final class KidsProfilePolicy {
  /// Le profil Enfants est TOUJOURS en mode enfants, même si
  /// la case disque a été oubliée. Un profil adulte suit la
  /// case (le parent l'allume ou non).
  static bool effectiveKidsMode({
    required bool isKidsProfile,
    required bool stored,
  }) =>
      isKidsProfile || stored;

  /// Quitter le profil Enfants (vers un autre) demande le code
  /// de CE profil. Y entrer, non : n'importe qui peut passer
  /// en mode protégé.
  static bool mustConfirmLeave({
    required bool currentIsKids,
    required String currentId,
    required String nextId,
  }) =>
      currentIsKids && currentId != nextId;

  /// Sur le profil Enfants, le parent ne coupe pas le mode
  /// depuis l'écran parental : il CHANGE de profil, avec le code.
  /// Sinon un enfant décocherait la case et verrait l'adulte.
  static bool canDisableKidsMode({required bool isKidsProfile}) => !isKidsProfile;
}

/// Filtre léger pour la RECHERCHE quand le mode enfants est actif.
///
/// On ne masque une chaîne que si on SAIT qu'elle est adulte
/// (genre déjà calculé, ou mot évident dans le titre). Un doute
/// → la chaîne RESTE. Règle du produit : ne jamais bloquer une
/// chaîne « par précaution ». Le Direct, lui, a son propre
/// filtre (déjà en place) qui attend le classement complet.
abstract final class KidsContentPolicy {
  static bool hideFromKids({
    required bool kidsMode,
    required bool? cachedIsAdult,
    required String name,
    required String category,
  }) {
    if (!kidsMode) return false;
    if (cachedIsAdult == false) return false;
    if (cachedIsAdult == true) return true;
    return looksAdult('$name $category');
  }

  /// Mots évidents seulement. On évite « sex » seul : il se
  /// cache dans « Essex » et masquerait une chaîne normale.
  static bool looksAdult(String text) {
    final String t = text.toLowerCase();
    const List<String> words = <String>[
      'xxx',
      'adult',
      'adulte',
      'adultes',
      'porn',
      'porno',
      'playboy',
      'dorcel',
      'erotic',
      'erotique',
      'erotica',
    ];
    for (final String w in words) {
      if (t.contains(w)) return true;
    }
    if (t.contains('+18')) return true;
    // « 18+ » oui, « 2018+ » non (le 18 est collé à un chiffre).
    return RegExp(r'(^|[^0-9])18\+').hasMatch(t);
  }
}
