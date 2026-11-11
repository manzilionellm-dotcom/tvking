import '../../features/channels/domain/channel_genre.dart';
import 'novatube_play_policy.dart';

/// Filtre partagé aux frontières des listes, du cinéma et des caches.
/// Le classement existant est conservé, sans dépendre du PIN ou du profil.
abstract final class NovatubeContentPolicy {
  static bool allows({required String name, required String category}) =>
      NovatubePlayPolicy.allowAdult ||
      !ChannelClassifier.isAdult(name, category);
}
