// Le sélecteur et les transports sont ceux de 7 MOTION. Le transfert du
// lecteur ZUNO attend la fermeture locale, sur Android comme sur Windows.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/data/cast_platform.dart';
import '../../cast/presentation/cast_picker_sheet.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';

/// Injection du sélecteur pour vérifier les courses sans récepteur réseau.
typedef CastPickerLauncher = Future<void> Function(
  BuildContext context, {
  required String streamUrl,
  required String title,
  String? imageUrl,
  required CastManager manager,
  required Object owner,
});

class DesktopCastControls extends StatefulWidget {
  const DesktopCastControls(
      {super.key,
      required this.controller,
      required this.streamUrl,
      required this.title,
      this.imageUrl,
      this.onHandoffChanged,
      this.prepareHandoff,
      this.enabled = true,
      this.disabledHint,
      this.manager,
      this.picker});
  final NativeVideoController controller;
  final String streamUrl;
  final String title;
  final String? imageUrl;
  final ValueChanged<bool>? onHandoffChanged;

  /// Met en pause les autres consommateurs avant le transfert. Un échec
  /// interdit le Cast : le lecteur local doit pouvoir rester seul.
  final Future<void> Function()? prepareHandoff;
  final bool enabled;
  final String? disabledHint;
  final CastManager? manager;
  final CastPickerLauncher? picker;
  @override
  State<DesktopCastControls> createState() => DesktopCastControlsState();
}

class DesktopCastControlsState extends State<DesktopCastControls> {
  CastManager? _manager;
  final Object _owner = Object();
  bool _handoff = false;
  bool _busy = false;
  bool _dead = false;
  int _revision = 0;
  String? _lastSentUrl;
  Future<void>? _closing;

  bool get ownsSession =>
      _manager?.ownsSession(_owner) == true && _manager!.isCasting;
  bool get _remoteActive =>
      _manager != null &&
      (_manager!.isCasting || _manager!.state == CastState.connecting);
  bool _current(int ticket) => mounted && !_dead && ticket == _revision;

  @override
  void initState() {
    super.initState();
    // Garde AVANT le singleton : l'édition TV ne lance ni découverte ni SDK,
    // même si ce widget est ajouté par erreur à l'un de ses écrans.
    if (!CastPlatform.canSend) return;
    _manager = widget.manager ?? CastManager.instance;
    _manager!.addListener(_changed);
  }

  @override
  void didUpdateWidget(DesktopCastControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ownsSession && !_busy && oldWidget.streamUrl != widget.streamUrl) {
      unawaited(_changeStream());
    }
  }

  void _setHandoff(bool active) {
    if (_handoff == active || _dead || !mounted) return;
    _handoff = active;
    widget.onHandoffChanged?.call(active);
  }

  void _changed() {
    if (_dead || !mounted) return;
    // Une recherche ou une suspension temporaire du SDK ne rend pas le
    // local. Seule la fin nettoyée du Cast permet cette reprise.
    if (_handoff && !_busy && !_remoteActive) unawaited(_finishHandoff());
    if (!_busy &&
        ownsSession &&
        _lastSentUrl != null &&
        _lastSentUrl != widget.streamUrl) {
      unawaited(_changeStream());
    }
    setState(() {});
  }

  Future<void> _resumeLocal(int ticket) async {
    final CastManager? manager = _manager;
    if (manager == null) return;
    await manager.disconnectForOwner(_owner);
    await manager.waitForSessionCleanup();
    if (!_current(ticket) || _remoteActive) return;
    await widget.controller.resumeAfterCast();
    if (!_current(ticket) || _remoteActive || widget.controller.castSuspended) {
      return;
    }
    _lastSentUrl = null;
    _setHandoff(false);
  }

  Future<void> _finishHandoff() async {
    if (_busy || _dead) return;
    final int ticket = ++_revision;
    setState(() => _busy = true);
    try {
      await _resumeLocal(ticket);
    } catch (_) {
      if (_current(ticket)) _showFailure();
    } finally {
      if (_current(ticket)) setState(() => _busy = false);
    }
  }

  // Les zaps arrivés pendant un envoi sont regroupés sur la sélection la
  // plus récente. Un ancien sélecteur ne récupère jamais une autre route.
  Future<void> _sendLatest(int ticket, {String? sentUrl}) async {
    final CastManager manager = _manager!;
    sentUrl ??= _lastSentUrl;
    while (_current(ticket) &&
        manager.ownsSession(_owner) &&
        manager.device != null &&
        sentUrl != widget.streamUrl) {
      final String url = widget.streamUrl;
      await manager.castTo(manager.device!,
          streamUrl: url,
          title: widget.title,
          imageUrl: widget.imageUrl,
          owner: _owner);
      sentUrl = url;
      if (!manager.isCasting) return;
      if (manager.ownsSession(_owner)) _lastSentUrl = url;
    }
  }

  Future<void> _changeStream() async {
    if (_busy || _dead || !ownsSession) return;
    final int ticket = ++_revision;
    setState(() => _busy = true);
    try {
      await _sendLatest(ticket);
    } catch (_) {
      if (_current(ticket)) _showFailure();
    } finally {
      if (_current(ticket)) {
        if (!ownsSession && !_remoteActive) {
          try {
            await _resumeLocal(ticket);
          } catch (_) {
            if (_current(ticket)) _showFailure();
          }
        }
        if (_current(ticket)) setState(() => _busy = false);
      }
    }
  }

  Future<void> _pick() async {
    if (_busy || _dead || !widget.enabled || _manager == null) return;
    final int ticket = ++_revision;
    setState(() => _busy = true);
    // Neutralise les watchdogs AVANT le premier await : l'EOF provoqué par
    // le stop local ne doit pas armer un secours sur une autre adresse.
    _setHandoff(true);
    try {
      await widget.prepareHandoff?.call();
      if (!_current(ticket)) return;
      await widget.controller.suspendForCast();
      if (!mounted || !_current(ticket)) return;
      final String requestedUrl = widget.streamUrl;
      final CastPickerLauncher picker = widget.picker ?? showCastPicker;
      await picker(context,
          streamUrl: requestedUrl,
          title: widget.title,
          imageUrl: widget.imageUrl,
          manager: _manager!,
          owner: _owner);
      if (!_current(ticket)) return;
      if (ownsSession) {
        _lastSentUrl = requestedUrl;
        await _sendLatest(ticket, sentUrl: requestedUrl);
      }
    } catch (_) {
      if (_current(ticket)) _showFailure();
    } finally {
      if (_current(ticket)) {
        // Fermer pendant la connexion annule seulement NOTRE tentative.
        if (!ownsSession) {
          try {
            await _resumeLocal(ticket);
          } catch (_) {
            if (_current(ticket)) _showFailure();
          }
        }
        if (_current(ticket)) setState(() => _busy = false);
      }
    }
  }

  Future<void> togglePause() async {
    if (!ownsSession || _busy || _manager!.isSuspended) return;
    final int ticket = _revision;
    setState(() => _busy = true);
    try {
      if (_manager!.state == CastState.paused) {
        await _manager!.resume();
      } else {
        await _manager!.pause();
      }
    } catch (_) {
      if (_current(ticket)) _showFailure();
    } finally {
      if (_current(ticket)) {
        setState(() => _busy = false);
        _changed();
      }
    }
  }

  Future<void> pause() async {
    if (ownsSession && !_busy && _manager!.state != CastState.paused) {
      await togglePause();
    }
  }

  Future<void> resume() async {
    if (ownsSession && !_busy && _manager!.state == CastState.paused) {
      await togglePause();
    }
  }

  Future<void> _stop() async {
    if (_busy || !ownsSession) return;
    await _finishHandoff();
  }

  void _showFailure() {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(context.l10n.castFailedRetry)));
  }

  /// La route attend cette fermeture avant de relancer ses téléchargements.
  /// Quitter ne relance jamais le lecteur en cours de destruction.
  Future<void> close() {
    _dead = true;
    ++_revision;
    return _closing ??= _closeOwnedSession();
  }

  Future<void> _closeOwnedSession() async {
    await _manager?.disconnectForOwner(_owner);
  }

  @override
  void dispose() {
    _manager?.removeListener(_changed);
    unawaited(close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!CastPlatform.canSend ||
        _manager == null ||
        !widget.streamUrl.startsWith(RegExp(r'https?://'))) {
      return const SizedBox.shrink();
    }
    final bool own = ownsSession;
    final bool paused = _manager!.state == CastState.paused;
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - TvDimens.safeH * 2)
              .clamp(TvDimens.posterW, double.infinity)),
      child: Container(
        decoration: BoxDecoration(
            color: TvTokens.panel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: own ? TvTokens.accent : TvTokens.line)),
        padding: const EdgeInsets.symmetric(
            horizontal: TvDimens.caption, vertical: TvDimens.rowGap),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (own) ...<Widget>[
            const Icon(Icons.cast_connected, color: TvTokens.accent),
            const SizedBox(width: TvDimens.caption),
            Flexible(
                child: Text(
                    _manager!.device?.displayName ??
                        context.l10n.castInProgressTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.caption))),
            IconButton(
                tooltip: paused
                    ? context.l10n.buttonResume
                    : context.l10n.playerPause,
                onPressed: _busy || _manager!.isSuspended ? null : togglePause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                    color: TvTokens.text)),
            IconButton(
                tooltip: context.l10n.castStopTooltip,
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined,
                    color: TvTokens.accent)),
          ] else
            Flexible(
                child: TextButton.icon(
                    onPressed: _busy || !widget.enabled || _remoteActive
                        ? null
                        : _pick,
                    icon: const Icon(Icons.cast, color: TvTokens.accent),
                    label: Text(
                        _busy
                            ? context.l10n.castConnecting
                            : !widget.enabled && widget.disabledHint != null
                                ? widget.disabledHint!
                                : context.l10n.castIdle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(TvDimens.caption,
                            color: TvTokens.text)))),
        ]),
      ),
    );
  }
}
