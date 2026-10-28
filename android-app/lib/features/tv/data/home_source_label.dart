import '../../playlists/domain/playlist.dart';
import '../../subscription/data/gold_trial_backend.dart';

/// La barre d'accueil ne révèle jamais l'identifiant de la ligne d'essai.
/// Le nom public suffit ; les sources personnelles gardent leur repère habituel.
String homeSourceLabel(List<Playlist> sources) {
  if (sources.isEmpty) return '';
  final Playlist active = sources.firstWhere(
    (Playlist source) => source.isActive,
    orElse: () => sources.first,
  );
  final String user = (active.xtreamUsername ?? '').trim();
  final String label = isGoldTrialPlaylist(active.name) || user.isEmpty
      ? active.name
      : '$user · ${active.name}';
  return sources.length > 1 ? '$label +${sources.length - 1}' : label;
}
