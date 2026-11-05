import 'channel.dart';

/// Construit une fois à l'arrivée du catalogue. Changer de catégorie au
/// D-pad devient une lecture de map, sans filtrer 25 000 chaînes à chaque pas.
class ChannelCategoryIndex {
  const ChannelCategoryIndex.empty() : categories = const <String>[],
    _groups = const <String, List<Channel>>{};

  ChannelCategoryIndex._(this.categories, this._groups);

  factory ChannelCategoryIndex(Iterable<Channel> channels,
      {required String Function(Channel) categoryOf}) {
    final Map<String, List<Channel>> groups = <String, List<Channel>>{};
    for (final Channel channel in channels) {
      (groups[categoryOf(channel)] ??= <Channel>[]).add(channel);
    }
    return ChannelCategoryIndex._(List<String>.unmodifiable(groups.keys),
      Map<String, List<Channel>>.unmodifiable(<String, List<Channel>>{
        for (final MapEntry<String, List<Channel>> e in groups.entries)
          e.key: List<Channel>.unmodifiable(e.value),
      }));
  }

  final List<String> categories;
  final Map<String, List<Channel>> _groups;
  List<Channel> channelsIn(String category) => _groups[category] ?? const <Channel>[];
  int countIn(String category) => _groups[category]?.length ?? 0;
  bool containsCategory(String? category) => _groups.containsKey(category);
}
