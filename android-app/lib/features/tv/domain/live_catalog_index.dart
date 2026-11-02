import '../../channels/domain/channel.dart';

/// Index d'un lot de chaînes du Direct, conservé pendant sa navigation.
///
/// Favoris, historique et tendances changent beaucoup plus souvent que le
/// catalogue. Ils réutilisent ces index : ajouter un favori ne doit pas
/// reconstruire trois tables de 50 000 chaînes sur le fil de l'interface.
/// L'écran crée un nouvel objet après chaque import ou filtre Mode Enfants.
class LiveCatalogIndex {
  LiveCatalogIndex(this._channels);

  final Iterable<Channel> _channels;

  // Même choix historique en cas d'identifiant doublé : le dernier gagne.
  late final Map<String, Channel> byId = <String, Channel>{
    for (final channel in _channels) channel.id: channel,
  };

  Map<String, Channel> _byName = const <String, Channel>{};
  Map<String, List<Channel>> _byCountry = const <String, List<Channel>>{};
  bool _curationReady = false;

  Map<String, List<Channel>> get byCountry => _byCountry;

  /// Appelé seulement quand le pré-calcul du lot a fini. Avant, les pays et
  /// tendances restent vides ; aucun getter coûteux n'est lancé ici.
  /// L'idempotence évite de rescanner le catalogue à chaque rayon actualisé.
  void completeCuration() {
    if (_curationReady) return;
    final names = <String, Channel>{};
    final countries = <String, List<Channel>>{};
    bool allCached = true;
    for (final channel in _channels) {
      final clean = ChannelPrecompute.cachedCleanName(channel);
      if (clean != null) {
        // Un nom partagé garde la première occurrence, comme le rapprochement
        // Tendances précédent (l'ordre du fournisseur reste déterminant).
        names.putIfAbsent(clean.trim().toLowerCase(), () => channel);
      }
      final cachedCountry = ChannelPrecompute.cachedCountry(channel);
      if (clean == null || !cachedCountry.known) allCached = false;
      final country = cachedCountry.country;
      if (channel.isLive && country != null) {
        (countries[country.code.toLowerCase()] ??= <Channel>[]).add(channel);
      }
    }
    _byName = names;
    _byCountry = countries;
    // Le pré-calcul est best-effort. Si son isolate a échoué, les getters des
    // lignes visibles peuvent remplir le cache plus tard : ne pas figer un
    // index incomplet, même si le chargement a déjà annoncé sa fin.
    _curationReady = allCached;
  }

  /// Seuls les quelques noms reçus du panel sont parcourus, pas la playlist.
  List<Channel> trending(List<String> names) {
    final result = <Channel>[];
    final seen = <String>{};
    for (final name in names) {
      final channel = _byName[name.trim().toLowerCase()];
      if (channel != null && seen.add(channel.id)) result.add(channel);
    }
    return result;
  }
}
