import '../../channels/domain/channel.dart';

/// Une passe sur le cache uniquement : grouper un bouquet ne déclenche aucune
/// détection sur le fil UI, et conserve l'ordre fournisseur dans chaque pays.
Map<String, List<Channel>> vipChannelGroups(Iterable<Channel> channels) {
  final groups = <String, List<Channel>>{};
  for (final channel in channels) {
    if (!channel.isLive) continue;
    final country = ChannelPrecompute.cachedCountry(channel).country;
    if (country != null) {
      (groups[country.code.toLowerCase()] ??= <Channel>[]).add(channel);
    }
  }
  return groups;
}
