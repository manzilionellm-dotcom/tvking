import '../../channels/domain/channel.dart';
import 'home_layout_repository.dart';

class HomeSectionView {
  const HomeSectionView(
      {required this.key,
      required this.title,
      required this.channels,
      required this.ribbon,
      required this.promoted});
  final String key, title, ribbon;
  final List<Channel> channels;
  final bool promoted;
}

const Map<String, (String, Set<ChannelGenre>)> homeGenreSections =
    <String, (String, Set<ChannelGenre>)>{
  HomeSectionKey.sport: ('Sport', <ChannelGenre>{ChannelGenre.sports}),
  HomeSectionKey.entertainment: (
    'Divertissement',
    <ChannelGenre>{
      ChannelGenre.entertainment,
      ChannelGenre.music,
      ChannelGenre.documentary
    }
  ),
  HomeSectionKey.info: ('Info', <ChannelGenre>{ChannelGenre.news}),
  HomeSectionKey.kids: ('Enfants', <ChannelGenre>{ChannelGenre.kids}),
  HomeSectionKey.general: (
    'Général',
    <ChannelGenre>{ChannelGenre.other, ChannelGenre.international}
  ),
  HomeSectionKey.cinema: (
    'Cinéma & séries',
    <ChannelGenre>{ChannelGenre.movies, ChannelGenre.series}
  ),
};
List<HomeSectionView> buildHomeSections(
    {required List<Channel> channels,
    required List<String> order,
    required HomeSectionConfig? Function(String) config,
    required Set<String> favorites,
    required List<String> recentIds}) {
  // Home shortcuts must never bypass the dedicated adult/parental gate.
  final List<Channel> safe =
      channels.where((Channel c) => c.genre != ChannelGenre.adult).toList();
  final Map<String, Channel> byId = <String, Channel>{
    for (final Channel c in safe) c.id: c
  };
  final List<HomeSectionView> result = <HomeSectionView>[];
  for (final String key in order) {
    final HomeSectionConfig? c = config(key);
    if (c?.enabled == false) continue;
    final (String, Set<ChannelGenre>)? genre = homeGenreSections[key];
    final String title = key == HomeSectionKey.recent
        ? 'Reprendre'
        : key == HomeSectionKey.favorites
            ? 'Favoris'
            : genre?.$1 ?? '';
    if (title.isEmpty) continue;
    final List<Channel> items = key == HomeSectionKey.recent
        ? <Channel>[
            for (final String id in recentIds)
              if (byId.containsKey(id)) byId[id]!
          ]
        : key == HomeSectionKey.favorites
            ? safe.where((Channel c) => favorites.contains(c.id)).toList()
            : safe.where((Channel c) => genre!.$2.contains(c.genre)).toList();
    if (items.isNotEmpty)
      result.add(HomeSectionView(
          key: key,
          title: title,
          channels: items,
          ribbon: c?.ribbon ?? '',
          promoted: c?.featured ?? false));
  }
  return result;
}

Channel? matchFeatured(List<Channel> channels, String name) {
  final String q = name.trim().toLowerCase();
  if (q.isEmpty) return null;
  final List<Channel> safe =
      channels.where((Channel c) => c.genre != ChannelGenre.adult).toList();
  for (final Channel c in safe) {
    if (c.name.toLowerCase() == q) return c;
  }
  for (final Channel c in safe) {
    if (c.name.toLowerCase().contains(q)) return c;
  }
  return null;
}
