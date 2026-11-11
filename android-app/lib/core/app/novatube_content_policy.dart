import '../../features/channels/domain/channel_genre.dart';
import '../../features/security/data/adult_access.dart';
import 'novatube_private_features.dart';

/// Filtre partagé aux frontières des listes, du cinéma et des caches.
/// Le build Play exclut ces contenus même avec un ancien cache ou un PIN.
abstract final class NovatubeContentPolicy {
  static bool isAdult({required String name, required String category,
      bool declaredAdult = false}) =>
      declaredAdult || ChannelClassifier.isAdult(name, category);

  /// L'APK privé conserve les éléments importés pour la section protégée.
  static bool canImport({required String name, required String category,
      bool declaredAdult = false}) =>
      NovatubePrivateFeatures.adultCatalogs ||
      !isAdult(name: name, category: category, declaredAdult: declaredAdult);

  /// Dernière garde avant une fiche ou un lecteur, y compris une route directe.
  static bool allows({required String name, required String category,
      bool declaredAdult = false}) =>
      !isAdult(name: name, category: category, declaredAdult: declaredAdult) ||
      AdultAccess.instance.canAccess;
}
