// Contrat entre l'ancien gestionnaire d'accueil et les rangées ZUNO.
// Seules les sections réellement équivalentes sont pilotées : « recent »
// correspond aux dernières chaînes et « favorites » aux favoris. Le cinéma,
// les rappels et la navigation gardent leurs propres règles d'accès.
import '../../simple_home/data/home_layout_repository.dart';
import 'home_shelves.dart';

const Set<String> kTvManagedHomeSections = <String>{
  HomeSectionKey.recent,
  HomeSectionKey.favorites,
};

bool tvHomeSectionVisible(String key, Map<String, HomeSectionConfig> layout) =>
    !kTvManagedHomeSections.contains(key) || layout[key]?.enabled != false;

/// Les rangées non pilotées gardent leur place relative. L'ordre distant
/// permute uniquement les emplacements des rangées compatibles présentes ;
/// il ne crée jamais de contenu et ne déplace pas les rappels du client.
List<String> tvHomeSectionOrder(
  Iterable<String> available,
  Map<String, HomeSectionConfig> layout,
) {
  final List<String> visible = available
      .where((String key) => tvHomeSectionVisible(key, layout))
      .toList();
  final List<String> managed = visible
      .where(kTvManagedHomeSections.contains)
      .toList();
  final Map<String, int> defaults = <String, int>{
    HomeSectionKey.recent: 0,
    HomeSectionKey.favorites: 1,
  };
  managed.sort((String a, String b) {
    final int comparison = (layout[a]?.position ?? defaults[a]!).compareTo(
      layout[b]?.position ?? defaults[b]!,
    );
    return comparison != 0 ? comparison : defaults[a]!.compareTo(defaults[b]!);
  });
  int next = 0;
  return <String>[
    for (final String key in visible)
      if (kTvManagedHomeSections.contains(key)) managed[next++] else key,
  ];
}

/// Empêche un écran vide avec de petites tuiles si le panel masque toutes
/// les rangées personnelles. Les grandes tuiles de navigation restent alors
/// accessibles, exactement comme sur un accueil sans historique.
bool hasVisibleTvHomeShelves(
  HomeShelfModel model,
  Map<String, HomeSectionConfig> layout,
) =>
    model.reminders.isNotEmpty ||
    model.continueWatching.isNotEmpty ||
    model.popular.isNotEmpty ||
    (model.resume.isNotEmpty &&
        tvHomeSectionVisible(HomeSectionKey.recent, layout)) ||
    (model.favorites.isNotEmpty &&
        tvHomeSectionVisible(HomeSectionKey.favorites, layout));

/// Le focus ne vise jamais une rangée qui vient d'être masquée. Ce choix
/// conserve la priorité des rappels et n'ouvre aucune chaîne automatiquement.
HomeShelfKind? visibleTvInitialShelf(
  HomeShelfKind? requested,
  HomeShelfModel model,
  Map<String, HomeSectionConfig> layout,
) {
  if (requested == null) return null;
  final bool resume =
      model.resume.isNotEmpty &&
      tvHomeSectionVisible(HomeSectionKey.recent, layout);
  final bool favorites =
      model.favorites.isNotEmpty &&
      tvHomeSectionVisible(HomeSectionKey.favorites, layout);
  if (requested == HomeShelfKind.resume && !resume ||
      requested == HomeShelfKind.favorites && !favorites) {
    return pickInitialShelf(
      hasSoonReminder: model.reminders.isNotEmpty,
      hasResume: resume,
      hasContinue: model.continueWatching.isNotEmpty,
      hasFavorites: favorites,
      hasPopular: model.popular.isNotEmpty,
    );
  }
  return requested;
}
