import '../../../core/app/app_platform.dart';
import '../../channels/domain/adult_channel_policy.dart';
import '../../channels/domain/channel.dart';
import '../../profiles/data/active_profile.dart';
import '../../security/data/adult_access.dart';
import '../../security/data/parental_controls.dart';

/// Métadonnées du média sélectionné. Une URL ne fournit ni sa provenance
/// ni son classement. `null` conserve donc un classement VOD inconnu.
class ZunoCastMedia {
  const ZunoCastMedia({
    required this.id,
    required this.streamUrl,
    this.playlistId,
    this.isAdult,
    this.isAllowedNow,
  }) : channel = null;

  ZunoCastMedia.channel(Channel value, {required this.streamUrl})
      : id = value.id,
        playlistId = value.playlistId,
        isAdult = isAdultChannel(value),
        channel = value,
        isAllowedNow = null;

  final String id;
  final String streamUrl;
  final int? playlistId;
  final bool? isAdult;
  final Channel? channel;

  /// Callback du média et de sa preuve, jamais de l'état d'un widget.
  final bool Function({AdultAccessGrant? adultAccess})? isAllowedNow;

  bool sameMedia(ZunoCastMedia other) =>
      id == other.id &&
      streamUrl == other.streamUrl &&
      playlistId == other.playlistId &&
      isAdult == other.isAdult &&
      identical(channel, other.channel) &&
      isAllowedNow == other.isAllowedNow;

  ZunoCastMediaAccess capture() => ZunoCastMediaAccess._(this);
}

/// Droit en mémoire lié au média, au profil et aux restrictions du geste.
/// Il ne dépend pas du widget : quitter le lecteur conserve un Cast valide,
/// mais une réponse tardive ne peut acquérir les droits du nouveau profil.
class ZunoCastMediaAccess {
  ZunoCastMediaAccess._(this.media)
      : _profile = ActiveProfile.instance.id,
        _scope = ActiveProfile.instance.scopeListenable.value,
        _generation = ParentalControls.instance.contentGeneration,
        _wasReady = ParentalControls.instance.protectsZuno &&
            ParentalControls.instance.contentReady;

  final ZunoCastMedia media;
  final String _profile;
  final int _scope;
  final int _generation;
  final bool _wasReady;

  bool allows(String streamUrl, {AdultAccessGrant? adultAccess}) {
    if (!AppPlatform.isZuno) return true;
    final controls = ParentalControls.instance;
    if (!_wasReady ||
        !controls.protectsZuno ||
        !controls.contentReady ||
        _profile != ActiveProfile.instance.id ||
        _scope != ActiveProfile.instance.scopeListenable.value ||
        _generation != controls.contentGeneration ||
        media.id.isEmpty ||
        media.streamUrl != streamUrl ||
        !ActiveProfile.instance.allowsPlaylist(media.playlistId) ||
        adultAccess?.isValid == false ||
        media.isAllowedNow?.call(adultAccess: adultAccess) == false) {
      return false;
    }
    final bool kids = controls.kidsMode.value;
    if (kids && media.isAdult != false) return false;
    if (media.isAdult == true && (kids || adultAccess == null)) return false;
    final channel = media.channel;
    return channel == null ||
        (!kids && adultAccess != null) ||
        !isHiddenFromNormalCatalog(channel);
  }
}
