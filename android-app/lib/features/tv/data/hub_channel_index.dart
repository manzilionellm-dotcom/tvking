import 'dart:collection';

import '../../channels/domain/channel.dart';
import 'home_shelves.dart';

/// Un seul index de l'accueil, lié au catalogue ET à sa portée. Les objets
/// Channel ne sont pas copiés. Invalider libère les références de l'ancienne
/// carte ; aucun catalogue historique n'est conservé par ce cache.
class HubChannelIndex {
  List<Channel>? _catalog;
  ({
    int generation,
    int scope,
    String profile,
    bool kids,
    bool kidsProfile
  })? _stamp;
  Map<String, Channel> _index = const <String, Channel>{};

  Map<String, Channel> read({
    required List<Channel> catalog,
    required int catalogGeneration,
    required int catalogScope,
    required int currentScope,
    required String profileId,
    required bool kidsMode,
    required bool kidsProfile,
    bool memoize = true,
  }) {
    // Le repli désactive le cache, jamais cette garde de portée.
    if (catalogScope != currentScope) {
      invalidate();
      return const <String, Channel>{};
    }
    final stamp = (
      generation: catalogGeneration,
      scope: currentScope,
      profile: profileId,
      kids: kidsMode,
      kidsProfile: kidsProfile,
    );
    if (memoize && identical(_catalog, catalog) && _stamp == stamp) {
      return _index;
    }
    final next =
        UnmodifiableMapView<String, Channel>(indexChannelsById(catalog));
    if (!memoize) {
      invalidate();
      return next;
    }
    _catalog = catalog;
    _stamp = stamp;
    _index = next;
    return next;
  }

  void invalidate() {
    _catalog = null;
    _stamp = null;
    _index = const <String, Channel>{};
  }
}
