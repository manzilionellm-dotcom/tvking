// Le sélecteur, la découverte et les transports sont ceux de 7 MOTION.
// Cette petite adaptation relie leur session aux lecteurs Zuno du PC et du téléphone Android.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import '../../../core/app/app_platform.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/data/cast_url_resolver.dart';
import '../../cast/domain/zuno_cast_media.dart';
import '../../security/data/adult_access.dart';
import '../../security/data/parental_controls.dart';
import '../../profiles/data/active_profile.dart';
import '../../channels/domain/adult_channel_policy.dart';
import '../../cast/data/cast_platform.dart';
import '../../cast/presentation/cast_picker_sheet.dart';
import '../../cast/presentation/screen_cast_sheet.dart';
import '../../channels/domain/channel.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import '../presentation/tv_live_preview.dart';
import 'media_kit_video_backend.dart';

int _channelRouteRevision = 0;

bool get zunoHasCastTarget =>
    CastPlatform.canSendFromZuno && CastManager.instance.hasTarget;

/// Un choix de chaîne depuis Accueil/Direct commande la TV déjà choisie.
/// On rend d'abord l'aperçu local puis on revalide le profil : ni une
/// réponse tardive ni un deuxième tap ne doivent ouvrir l'ancienne chaîne.
/// `true` signifie que ce choix appartient au Cast, même si le récepteur
/// échoue : on ne démarre jamais un deuxième flux local comme repli caché.
Future<bool> routeZunoChannelToCast(
  BuildContext context, {
  required List<Channel> channels,
  required Channel channel,
  AdultAccessGrant? adultAccess,
  String? streamUrl,
  bool Function()? stillAllowed,
  CastManager? manager,
  Future<void> Function()? releaseLocal,
}) async {
  final cast = manager ?? CastManager.instance;
  if (!CastPlatform.canSendFromZuno || !cast.hasTarget) return false;
  final int revision = ++_channelRouteRevision;
  final int scope = ActiveProfile.instance.scopeListenable.value;
  final int generation = ParentalControls.instance.contentGeneration;
  bool allowed() =>
      context.mounted &&
      revision == _channelRouteRevision &&
      scope == ActiveProfile.instance.scopeListenable.value &&
      ActiveProfile.instance.allowsPlaylist(channel.playlistId) &&
      (adultAccess?.isValid ?? !isAdultChannel(channel)) &&
      (!AppPlatform.isZuno ||
          (ParentalControls.instance.protectsZuno &&
           ParentalControls.instance.contentReady &&
           generation == ParentalControls.instance.contentGeneration &&
           ((!ParentalControls.instance.kidsMode.value && adultAccess != null) ||
            !isHiddenFromNormalCatalog(channel)))) &&
      (stillAllowed?.call() ?? true);
  if (!allowed()) return true;
  await (releaseLocal ?? TvLivePreview.releaseActive)();
  if (!allowed()) return true;
  final String url = streamUrl ?? await CastUrlResolver.resolve(channel);
  if (!allowed()) return true;
  cast.setCastPlaylist(channels, channel, adultAccess: adultAccess);
  try {
    await cast.castChannelOnCurrentSession(
      streamUrl: url,
      title: channel.cleanName,
      channelName: channel.cleanName,
      channelGenre: channel.category,
      imageUrl: channel.logoUrl,
      channel: channel,
      adultAccess: adultAccess,
    );
  } catch (_) {
    // Le sélecteur affiche l'erreur du moteur et permet une relance ou
    // un changement de TV ; la chaîne n'est pas rouverte sur le mobile.
    if (allowed()) {
      await showCastPicker(context,
          streamUrl: url,
          title: channel.cleanName,
          imageUrl: channel.logoUrl,
          adultAccess: adultAccess,
          manager: cast);
    }
  }
  return true;
}

typedef ZunoCastPicker = Future<void> Function(
  BuildContext context, {
  required String streamUrl,
  required String title,
  String? imageUrl,
  AdultAccessGrant? adultAccess,
});

class DesktopCastControls extends StatefulWidget {
  /// Le récepteur lit une URL réseau. Un téléchargement local reste réservé
  /// au lecteur du téléphone et ne doit jamais déclencher une passation.
  static bool supportsSource(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  const DesktopCastControls(
      {super.key,
      required this.controller,
      required this.streamUrl,
      required this.title,
      this.imageUrl,
      this.onHandoffChanged,
      this.manager,
      this.picker,
      this.adultAccess,
      this.zunoMedia,
      this.channels,
      this.channel,
      this.onChannelChanged,
      this.castOnOpen = false});
  final NativeVideoController controller;
  final String streamUrl;
  final String title;
  final String? imageUrl;
  final AdultAccessGrant? adultAccess;
  final ZunoCastMedia? zunoMedia;
  final List<Channel>? channels;
  final Channel? channel;
  final ValueChanged<Channel>? onChannelChanged;
  final ValueChanged<bool>? onHandoffChanged;

  /// Vrai seulement lorsque cette route vient d'un choix explicite de média.
  final bool castOnOpen;
  // Injection pour tester annulation / passation sans récepteur physique.
  final CastManager? manager;
  final ZunoCastPicker? picker;
  @override
  State<DesktopCastControls> createState() => DesktopCastControlsState();
}

class DesktopCastControlsState extends State<DesktopCastControls> {
  late final CastManager _manager = widget.manager ?? CastManager.instance;
  bool _owns = false;
  bool _busy = false;
  bool _dead = false;
  bool _pickerPending = false;
  bool _pickerStartedPlayback = false;
  int? _pickerOwnedRevision;
  bool _localHandoff = false;
  bool _castEndedIdle = false;
  bool _hadCast = false;
  bool _screenActive = false;
  Future<void> _localTail = Future<void>.value();
  int _revision = 0;
  late final int _scope = ActiveProfile.instance.scopeListenable.value;
  ZunoCastMediaAccess? _zunoAccess;
  int _zunoGeneration = 0;
  bool get ownsSession => _owns;
  bool get waitingForLocalPlay => _castEndedIdle;
  bool get _hasRemoteSource =>
      DesktopCastControls.supportsSource(widget.streamUrl);
  bool get _accessAllowed =>
      _scope == ActiveProfile.instance.scopeListenable.value &&
      (widget.adultAccess?.isValid ?? true) &&
      (!AppPlatform.isZuno ||
          (ParentalControls.instance.protectsZuno &&
           ParentalControls.instance.contentReady &&
           _zunoGeneration == ParentalControls.instance.contentGeneration &&
           (_zunoAccess?.allows(widget.streamUrl,
                   adultAccess: widget.adultAccess) ??
               (!ParentalControls.instance.kidsMode.value &&
                ActiveProfile.instance.playlistIds == null))));

  void _captureZunoMedia() {
    if (!AppPlatform.isZuno) return;
    final channel = widget.channel;
    final media = widget.zunoMedia ?? (channel == null ? null :
        ZunoCastMedia.channel(channel, streamUrl: widget.streamUrl));
    _zunoAccess = media?.capture();
    _zunoGeneration = ParentalControls.instance.contentGeneration;
  }

  @override
  void initState() {
    super.initState();
    _captureZunoMedia();
    _manager.addListener(_changed);
    ActiveProfile.instance.scopeListenable.addListener(_accessChanged);
    widget.adultAccess?.addListener(_accessChanged);
    ParentalControls.instance.readiness.addListener(_accessChanged);
    ParentalControls.instance.kidsMode.addListener(_accessChanged);
    if (CastPlatform.canSendFromZuno &&
        _accessAllowed &&
        _hasRemoteSource &&
        (_manager.hasActiveSession || _manager.hasTarget)) {
      // Le Cast appartient au moteur partagé, pas à cette route. Un lecteur
      // ouvert pendant sa session ferme son flux local, sans envoyer une
      // nouvelle URL au récepteur. Le natif mémorise ce verrou avant attach.
      _owns = _manager.hasActiveSession;
      _hadCast = _owns;
      _localHandoff = true;
      _localTail = _suspendLocal(widget.controller).catchError((Object _) {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _localHandoff) widget.onHandoffChanged?.call(true);
        if (mounted &&
            _accessAllowed &&
            (widget.castOnOpen || !_manager.hasActiveSession)) {
          unawaited(_changeStream());
        }
      });
    }
  }

  @override
  void didUpdateWidget(DesktopCastControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppPlatform.isZuno &&
        (oldWidget.streamUrl != widget.streamUrl ||
         !identical(oldWidget.channel, widget.channel) ||
         (oldWidget.zunoMedia == null
             ? widget.zunoMedia != null
             : widget.zunoMedia == null ||
               !oldWidget.zunoMedia!.sameMedia(widget.zunoMedia!)))) {
      ++_revision;
      _captureZunoMedia();
    }
    if (!identical(oldWidget.adultAccess, widget.adultAccess)) {
      oldWidget.adultAccess?.removeListener(_accessChanged);
      widget.adultAccess?.addListener(_accessChanged);
      _accessChanged();
    }
    if (oldWidget.controller != widget.controller && _localHandoff) {
      _localTail = _suspendLocal(widget.controller).catchError((Object _) {});
    }
    if ((_owns || _manager.hasTarget) &&
        oldWidget.streamUrl != widget.streamUrl &&
        (widget.channel == null ||
            _manager.currentCastChannel?.id != widget.channel!.id ||
            _manager.currentCastChannel?.playlistId !=
                widget.channel!.playlistId)) {
      unawaited(_changeStream());
    }
  }

  void _accessChanged() {
    if (_dead || !mounted || _accessAllowed) return;
    ++_revision;
    // Ne jamais restaurer le lecteur local lorsque la session distante
    // protégée s'arrête. Le propriétaire ferme également ses routes.
    unawaited(_setLocalHandoff(true).catchError((Object _) {}));
    setState(() {});
  }

  void _changed() {
    if (_dead || !mounted || !_accessAllowed || !_hasRemoteSource) return;
    if (_pickerPending && _manager.isCasting) _pickerStartedPlayback = true;
    if (_manager.hasActiveSession) {
      if (_manager.isCasting) _hadCast = true;
      unawaited(_setLocalHandoff(true).catchError((Object _) {}));
    }
    final Channel? current = _manager.currentCastChannel;
    if (current != null && _manager.isCasting) {
      widget.onChannelChanged?.call(current);
    }
    if (!_busy) _syncSession();
    setState(() {});
  }

  void _syncSession() {
    _owns = _manager.hasActiveSession;
    _castEndedIdle = !_owns && _hadCast && _manager.state != CastState.error;
    if (_manager.state == CastState.error) _hadCast = false;
    unawaited(_setLocalHandoff(_owns || _castEndedIdle || _screenActive)
        .catchError((Object _) {}));
  }

  Future<void> _setLocalHandoff(bool active) {
    if (!_accessAllowed) active = true;
    if (_localHandoff == active) return _localTail;
    _localHandoff = active;
    widget.onHandoffChanged?.call(active);
    final NativeVideoController controller = widget.controller;
    // Une reprise devenue périmée ne doit pas rouvrir le téléphone après
    // une reconnexion du récepteur. Les commandes natives gardent leur ordre.
    final Future<void> operation = _localTail.then((_) async {
      if (_dead || !identical(controller, widget.controller)) return;
      if (_localHandoff) {
        await _suspendLocal(controller);
      } else {
        await _resumeLocal(controller);
      }
    });
    _localTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _changeStream() async {
    final device = _manager.device ?? _manager.selectedDevice;
    if (device == null || !_accessAllowed || !_hasRemoteSource) return;
    final int ticket = ++_revision;
    _busy = true;
    try {
      await _setLocalHandoff(true);
      if (!mounted ||
          ticket != _revision ||
          !_accessAllowed ||
          !_hasRemoteSource) return;
      _sharePlaylist();
      await _manager.castTo(device,
          streamUrl: widget.streamUrl,
          title: widget.title,
          imageUrl: widget.imageUrl,
          adultAccess: widget.adultAccess);
    } catch (_) {
      // Le moteur partagé expose l'issue ; le finally réconcilie le local.
    } finally {
      if (mounted && ticket == _revision) {
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }

  Future<void> _pick() async {
    if (_busy || !_accessAllowed || !_hasRemoteSource) return;
    final int ticket = ++_revision;
    final String requestedUrl = widget.streamUrl;
    setState(() => _busy = true);
    _pickerPending = true;
    _pickerStartedPlayback = false;
    _pickerOwnedRevision = null;
    // Fermer le flux local avant le Cast évite de consommer deux connexions
    // chez les fournisseurs qui n’en autorisent qu’une. Le film garde sa position.
    try {
      await _setLocalHandoff(true);
      if (!mounted ||
          ticket != _revision ||
          !_accessAllowed ||
          !_hasRemoteSource) return;
      _sharePlaylist();
      final picker = widget.picker;
      if (picker == null) {
        await showCastPicker(context,
            streamUrl: widget.streamUrl,
            title: widget.title,
            imageUrl: widget.imageUrl,
            adultAccess: widget.adultAccess,
            manager: _manager,
            onAttempt: (revision) => _pickerOwnedRevision = revision);
      } else {
        // L'injection de test peut lancer sa tentative avant de rendre la
        // Future du dialogue. Le vrai picker rapporte explicitement son jeton.
        final operation = picker(context,
            streamUrl: widget.streamUrl,
            title: widget.title,
            imageUrl: widget.imageUrl,
            adultAccess: widget.adultAccess);
        _pickerOwnedRevision = _manager.sessionRevision;
        await operation;
      }
      if (!mounted || ticket != _revision ||
          (AppPlatform.isZuno && !_accessAllowed)) {
        return;
      }
      _owns = _manager.hasActiveSession &&
          (_manager.isCasting || _pickerStartedPlayback);
      if (!_owns) {
        // Fermer le sélecteur pendant une connexion annule aussi celle-ci :
        // une réponse tardive ne doit pas démarrer la TV après le retour au PC.
        if (_manager.state != CastState.error &&
            _pickerOwnedRevision == _manager.sessionRevision) {
          await _manager.disconnect();
        }
      } else if (requestedUrl != widget.streamUrl &&
          _hasRemoteSource &&
          _manager.device != null &&
          _pickerOwnedRevision == _manager.sessionRevision) {
        if (AppPlatform.isZuno) _sharePlaylist();
        await _manager.castTo(_manager.device!,
            streamUrl: widget.streamUrl,
            title: widget.title,
            imageUrl: widget.imageUrl,
            adultAccess: widget.adultAccess);
        if (mounted && ticket == _revision) _owns = _manager.hasActiveSession;
      }
    } catch (_) {
      if (mounted &&
          ticket == _revision &&
          !_manager.isCasting &&
          !_pickerStartedPlayback &&
          _manager.state != CastState.error &&
          _pickerOwnedRevision == _manager.sessionRevision) {
        await _manager.disconnect();
      }
    } finally {
      if (mounted && ticket == _revision) {
        _pickerPending = false;
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }

  Future<void> _suspendLocal(NativeVideoController controller) =>
      CastPlatform.isWindows
          ? MediaKitVideoBackend.suspendForCast(controller)
          : controller.suspendForCast();

  Future<void> _resumeLocal(NativeVideoController controller) async {
    if (CastPlatform.isWindows) {
      MediaKitVideoBackend.resumeAfterCast(controller);
    } else {
      await controller.resumeAfterCast();
    }
  }

  Future<void> togglePause() async {
    if (_castEndedIdle) {
      await resumeLocalPlayback();
      return;
    }
    if (!_owns || _busy || !_accessAllowed) return;
    setState(() => _busy = true);
    try {
      if (_manager.state == CastState.paused) {
        await _manager.resume();
      } else {
        await _manager.pause();
      }
    } finally {
      if (mounted) {
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }

  Future<void> pause() async {
    if (_owns && !_busy && _accessAllowed) await _manager.pause();
  }

  Future<void> resume() async {
    if (_owns && !_busy && _accessAllowed) await _manager.resume();
  }

  Future<void> resumeLocalPlayback() async {
    if (!_accessAllowed || _manager.hasActiveSession) return;
    // « Reprendre ici » est un choix explicite : ne pas conserver une
    // cible cachée qui renverrait le prochain zap sur la TV arrêtée.
    if (_manager.hasTarget) await _manager.disconnect();
    if (!mounted || !_accessAllowed) return;
    _hadCast = false;
    _castEndedIdle = false;
    await _setLocalHandoff(false);
    if (mounted) setState(() {});
  }

  void _sharePlaylist() {
    final list = widget.channels;
    final channel = widget.channel;
    if (list != null && channel != null) {
      _manager.setCastPlaylist(list, channel, adultAccess: widget.adultAccess);
    } else {
      _manager.clearCastPlaylist();
    }
    if (AppPlatform.isZuno) _manager.setZunoMediaAccess(_zunoAccess);
  }

  Future<void> _screen() async {
    if (_busy || !_accessAllowed || !_hasRemoteSource) return;
    final int ticket = ++_revision;
    setState(() {
      _busy = true;
      _screenActive = true;
    });
    try {
      await _setLocalHandoff(true);
      if (!mounted ||
          ticket != _revision ||
          !_accessAllowed ||
          !_hasRemoteSource) return;
      // Changer de mode rend d'abord la connexion du récepteur précédent.
      if (_manager.hasActiveSession) await _manager.disconnect();
      if (!mounted ||
          ticket != _revision ||
          !_accessAllowed ||
          !_hasRemoteSource) return;
      await showScreenCastSheet(context,
          streamUrl: widget.streamUrl,
          title: widget.title,
          adultAccess: widget.adultAccess, onActive: () {
        _hadCast = true;
      });
    } finally {
      if (mounted && ticket == _revision) {
        _screenActive = false;
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }

  Future<void> _stop() async {
    if (_busy || !_accessAllowed) return;
    ++_revision;
    setState(() {
      _busy = true;
      _owns = false;
    });
    try {
      await _manager.disconnect();
    } finally {
      if (mounted) {
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _dead = true;
    ++_revision;
    _manager.removeListener(_changed);
    ActiveProfile.instance.scopeListenable.removeListener(_accessChanged);
    widget.adultAccess?.removeListener(_accessChanged);
    ParentalControls.instance.readiness.removeListener(_accessChanged);
    ParentalControls.instance.kidsMode.removeListener(_accessChanged);
    // Comme dans 7 MOTION, une session établie survit à la route. Seul un
    // choix encore en attente est annulé : il ne doit pas démarrer plus tard
    // après la fermeture de son sélecteur. Le moteur possède ses relais.
    final bool established = _manager.hasActiveSession &&
        (_manager.isCasting || _pickerStartedPlayback || _owns);
    if (_pickerPending &&
        !established &&
        _scope == ActiveProfile.instance.scopeListenable.value &&
        _pickerOwnedRevision == _manager.sessionRevision) {
      unawaited(_manager.disconnect());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessAllowed || !CastPlatform.canSendFromZuno || !_hasRemoteSource)
      return const SizedBox.shrink();
    final palette = TvAppTokens.playbackOf(context);
    return Container(
      decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border:
              Border.all(color: _owns ? palette.accentBright : palette.line)),
      padding: const EdgeInsets.symmetric(
          horizontal: TvDimens.caption, vertical: TvDimens.rowGap),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (_owns) ...<Widget>[
          Icon(Icons.cast_connected, color: palette.accentBright),
          const SizedBox(width: TvDimens.caption),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: TvDimens.posterW * 2),
              child: Text(
                  _manager.device?.displayName ??
                      context.l10n.castInProgressTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.caption))),
          IconButton(
              tooltip: _manager.state == CastState.paused
                  ? context.l10n.buttonResume
                  : context.l10n.playerPause,
              onPressed: _busy ? null : togglePause,
              icon: Icon(
                  _manager.state == CastState.paused
                      ? Icons.play_arrow
                      : Icons.pause,
                  color: palette.text)),
          IconButton(
              tooltip: context.l10n.castStopTooltip,
              onPressed: _busy ? null : _stop,
              icon: Icon(Icons.stop_circle_outlined,
                  color: palette.accentBright)),
          if (_manager.canZapOnCast) ...<Widget>[
            IconButton(
                onPressed: _busy ? null : _manager.zapCastPrev,
                icon: const Icon(Icons.skip_previous_rounded)),
            IconButton(
                onPressed: _busy ? null : _manager.zapCastNext,
                icon: const Icon(Icons.skip_next_rounded)),
          ],
        ],
        if (_castEndedIdle)
          IconButton(
              tooltip: context.l10n.buttonResume,
              onPressed: _busy ? null : resumeLocalPlayback,
              icon: const Icon(Icons.play_arrow_rounded)),
        TextButton.icon(
            onPressed: _busy ? null : _pick,
            icon: Icon(Icons.cast, color: palette.accentBright),
            label: Text(
                _busy ? context.l10n.castConnecting : context.l10n.castIdle,
                style: TvTokens.ui(TvDimens.caption, color: palette.text))),
        IconButton(
            tooltip: context.l10n.playerScreenCast,
            onPressed: _busy ? null : _screen,
            icon: const Icon(Icons.screen_share_rounded)),
      ]),
    );
  }
}
