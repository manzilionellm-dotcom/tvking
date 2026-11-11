import '../../channels/domain/channel.dart';

/// Décompte d'un import M3U courant. Les entrées ignorées n'ont jamais été
/// enregistrées : ce nombre ne doit pas être présenté comme une ligne SQLite.
class M3uImportCounts {
  const M3uImportCounts({
    required this.validEntries,
    required this.retainedEntries,
  });

  final int validEntries;
  final int retainedEntries;
  int get skippedEntries => validEntries - retainedEntries;
  bool get truncated => skippedEntries > 0;
}

/// Les deux cartes viennent de la même lecture SQL. La troisième est calculée
/// sur les seuls objets déjà chargés, après dédoublonnage et filtre du flavor.
class ChannelReadCounts {
  ChannelReadCounts({
    required Map<int, int> storedRows,
    required Map<int, int> loadedRows,
    Map<int, int> loadedChannels = const <int, int>{},
  }) : storedRows = Map<int, int>.unmodifiable(storedRows),
       loadedRows = Map<int, int>.unmodifiable(loadedRows),
       loadedChannels = Map<int, int>.unmodifiable(loadedChannels);

  final Map<int, int> storedRows;
  final Map<int, int> loadedRows;
  final Map<int, int> loadedChannels;

  ChannelReadCounts withChannels(List<Channel> channels) {
    final counts = <int, int>{};
    for (final channel in channels) {
      final id = channel.playlistId;
      if (id != null) {
        counts.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return ChannelReadCounts(
      storedRows: storedRows,
      loadedRows: loadedRows,
      loadedChannels: counts,
    );
  }
}

/// Aucun lien de flux ni identifiant fournisseur. Le nom est réservé à l'UI
/// autorisée ; les traces utilisent uniquement playlistId et les compteurs.
class ChannelLimitSource {
  const ChannelLimitSource({
    required this.playlistId,
    required this.name,
    required this.storedRows,
    required this.loadedRows,
    required this.loadedChannels,
    this.importCounts,
  });

  final int playlistId;
  final String name;
  final int storedRows;
  final int loadedRows;
  final int loadedChannels;
  final M3uImportCounts? importCounts;
  bool get loadLimited => storedRows > loadedRows;
  bool get affected => loadLimited || (importCounts?.truncated ?? false);
}

/// Instantané lié au profil et à sa portée, jamais réutilisé après bascule.
/// « Chargé » ne signifie pas « affiché » : les filtres de l'écran s'appliquent
/// ensuite et ne doivent pas être déduits de la présence dans ce catalogue.
class ChannelLimitSnapshot {
  ChannelLimitSnapshot({
    required this.profileId,
    required this.scope,
    required this.limit,
    required List<ChannelLimitSource> sources,
  }) : sources = List<ChannelLimitSource>.unmodifiable(sources);

  final String profileId;
  final int scope;
  final int limit;
  final List<ChannelLimitSource> sources;
  int get storedRows =>
      sources.fold(0, (sum, source) => sum + source.storedRows);
  int get loadedRows =>
      sources.fold(0, (sum, source) => sum + source.loadedRows);
  int get loadedChannels =>
      sources.fold(0, (sum, source) => sum + source.loadedChannels);
  List<ChannelLimitSource> get affectedSources =>
      sources.where((source) => source.affected).toList(growable: false);
  bool get hasLimit => sources.any((source) => source.affected);
  bool get hasLoadLimit => sources.any((source) => source.loadLimited);
}
