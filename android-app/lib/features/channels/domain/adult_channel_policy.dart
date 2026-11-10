import 'channel.dart';

// Expando suit la durée de vie des objets Channel : aucun second catalogue
// conservé en mémoire, aucune classification répétée à chaque reconstruction.
final Expando<bool> _adultByChannel = Expando<bool>('adult-channel-policy');

/// Même vocabulaire que le classificateur général, sans calculer pays,
/// qualité et tous les autres genres lorsque son cache est encore froid.
bool isAdultChannel(Channel channel) {
  final ChannelGenre? ready = ChannelPrecompute.cachedGenre(channel);
  if (ready != null) return ready == ChannelGenre.adult;
  return _adultByChannel[channel] ??= ChannelClassifier.isAdult(
    channel.name,
    channel.category,
  );
}
