// Le sélecteur, la découverte et les transports sont ceux de 7 MOTION.
// Cette petite adaptation relie leur session aux lecteurs Zuno du PC et du téléphone Android.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/data/cast_platform.dart';
import '../../cast/presentation/cast_picker_sheet.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'media_kit_video_backend.dart';

typedef ZunoCastPicker = Future<void> Function(BuildContext context, {
  required String streamUrl, required String title, String? imageUrl,
});

class DesktopCastControls extends StatefulWidget {
  const DesktopCastControls({super.key, required this.controller,
    required this.streamUrl, required this.title, this.imageUrl,
    this.onHandoffChanged, this.manager, this.picker});
  final NativeVideoController controller;
  final String streamUrl;
  final String title;
  final String? imageUrl;
  final ValueChanged<bool>? onHandoffChanged;
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
  bool _localHandoff = false;
  Future<void> _localTail = Future<void>.value();
  int _revision = 0;
  bool get ownsSession => _owns;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_changed);
    if (_manager.hasActiveSession) {
      // Le Cast appartient au moteur partagé, pas à cette route. Un lecteur
      // ouvert pendant sa session ferme son flux local, sans envoyer une
      // nouvelle URL au récepteur. Le natif mémorise ce verrou avant attach.
      _owns = true;
      _localHandoff = true;
      _localTail = _suspendLocal(widget.controller).catchError((Object _) {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _localHandoff) widget.onHandoffChanged?.call(true);
      });
    }
  }
  @override
  void didUpdateWidget(DesktopCastControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller && _localHandoff) {
      _localTail = _suspendLocal(widget.controller).catchError((Object _) {});
    }
    if (_owns && oldWidget.streamUrl != widget.streamUrl) unawaited(_changeStream());
  }
  void _changed() {
    if (_dead || !mounted) return;
    if (_pickerPending && _manager.isCasting) _pickerStartedPlayback = true;
    if (!_busy) _syncSession();
    setState(() {});
  }

  void _syncSession() {
    _owns = _manager.hasActiveSession;
    unawaited(_setLocalHandoff(_owns).catchError((Object _) {}));
  }

  Future<void> _setLocalHandoff(bool active) {
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
    final device = _manager.device;
    if (device == null) return;
    final int ticket = ++_revision;
    _busy = true;
    try {
      await _localTail;
      if (!mounted || ticket != _revision) return;
      await _manager.castTo(device, streamUrl: widget.streamUrl,
          title: widget.title, imageUrl: widget.imageUrl);
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
    if (_busy) return;
    final int ticket = ++_revision;
    final String requestedUrl = widget.streamUrl;
    setState(() => _busy = true);
    _pickerPending = true;
    _pickerStartedPlayback = false;
    // Fermer le flux local avant le Cast évite de consommer deux connexions
    // chez les fournisseurs qui n’en autorisent qu’une. Le film garde sa position.
    try {
      await _setLocalHandoff(true);
      if (!mounted || ticket != _revision) return;
      await (widget.picker ?? showCastPicker)(context, streamUrl: widget.streamUrl,
          title: widget.title, imageUrl: widget.imageUrl);
      if (!mounted || ticket != _revision) return;
      _owns = _manager.hasActiveSession &&
          (_manager.isCasting || _pickerStartedPlayback);
      if (!_owns) {
        // Fermer le sélecteur pendant une connexion annule aussi celle-ci :
        // une réponse tardive ne doit pas démarrer la TV après le retour au PC.
        await _manager.disconnect();
      } else if (requestedUrl != widget.streamUrl && _manager.device != null) {
        await _manager.castTo(_manager.device!, streamUrl: widget.streamUrl,
            title: widget.title, imageUrl: widget.imageUrl);
        if (mounted && ticket == _revision) _owns = _manager.hasActiveSession;
      }
    } catch (_) {
      if (mounted && ticket == _revision &&
          !_manager.isCasting && !_pickerStartedPlayback) {
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

  Future<void> _suspendLocal(NativeVideoController controller) => CastPlatform.isWindows
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
    if (!_owns || _busy) return;
    setState(() => _busy = true);
    try {
      if (_manager.state == CastState.paused) { await _manager.resume(); }
      else { await _manager.pause(); }
    } finally {
      if (mounted) {
        _busy = false;
        _syncSession();
        setState(() {});
      }
    }
  }
  Future<void> pause() async { if (_owns && !_busy) await _manager.pause(); }
  Future<void> resume() async { if (_owns && !_busy) await _manager.resume(); }
  Future<void> _stop() async {
    if (_busy) return;
    ++_revision;
    setState(() { _busy = true; _owns = false; });
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
    _dead = true; ++_revision;
    _manager.removeListener(_changed);
    // Comme dans 7 MOTION, une session établie survit à la route. Seul un
    // choix encore en attente est annulé : il ne doit pas démarrer plus tard
    // après la fermeture de son sélecteur. Le moteur possède ses relais.
    final bool established = _manager.hasActiveSession &&
        (_manager.isCasting || _pickerStartedPlayback || _owns);
    if (_pickerPending && !established) unawaited(_manager.disconnect());
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (!CastPlatform.canSendFromZuno || !widget.streamUrl.startsWith(RegExp(r'https?://'))) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: TvTokens.panel,
        borderRadius: BorderRadius.circular(TvTokens.rButton),
        border: Border.all(color: _owns ? TvTokens.accent : TvTokens.line)),
      padding: const EdgeInsets.symmetric(horizontal: TvDimens.caption, vertical: TvDimens.rowGap),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (_owns) ...<Widget>[
          const Icon(Icons.cast_connected, color: TvTokens.accent),
          const SizedBox(width: TvDimens.caption),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: TvDimens.posterW * 2),
            child: Text(_manager.device?.displayName ?? context.l10n.castInProgressTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TvTokens.ui(TvDimens.caption))),
          IconButton(tooltip: _manager.state == CastState.paused ? context.l10n.buttonResume : context.l10n.playerPause,
            onPressed: _busy ? null : togglePause,
            icon: Icon(_manager.state == CastState.paused ? Icons.play_arrow : Icons.pause, color: TvTokens.text)),
          IconButton(tooltip: context.l10n.castStopTooltip, onPressed: _busy ? null : _stop,
            icon: const Icon(Icons.stop_circle_outlined, color: TvTokens.accent)),
        ] else TextButton.icon(onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.cast, color: TvTokens.accent),
          label: Text(_busy ? context.l10n.castConnecting : context.l10n.castIdle,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.text))),
      ]),
    );
  }
}
