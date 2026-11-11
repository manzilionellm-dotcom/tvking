import '../../../core/app/app_platform.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/data/active_profile.dart';
import '../../security/data/parental_controls.dart';
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

/// Filtre des surfaces normales de ZUNO : aucune permission provisoire et
/// aucun titre/miniature non classé pour un enfant. L'espace adulte continue
/// d'utiliser son autorisation explicite et son filtre séparé.
bool isHiddenFromNormalCatalog(Channel channel) {
  if (isAdultChannel(channel)) return true;
  if (!AppPlatform.isZuno) return false;
  if (!ActiveProfile.instance.allowsPlaylist(channel.playlistId)) return true;
  final controls = ParentalControls.instance;
  if (!controls.contentReady) return true;
  if (!controls.kidsMode.value && !ProfileRepository.instance.activeIsKids) return false;
  final genre = ChannelPrecompute.cachedGenre(channel);
  return genre == null || genre == ChannelGenre.other;
}
