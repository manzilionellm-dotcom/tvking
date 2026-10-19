// Le sélecteur, la découverte et les transports sont ceux de 7 MOTION.
// Cette petite adaptation relie leur session au lecteur ZUNO de Windows.
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

class DesktopCastControls extends StatefulWidget {
  const DesktopCastControls({super.key, required this.controller,
    required this.streamUrl, required this.title, this.imageUrl});
  final NativeVideoController controller;
  final String streamUrl;
  final String title;
  final String? imageUrl;
  @override
  State<DesktopCastControls> createState() => DesktopCastControlsState();
}

class DesktopCastControlsState extends State<DesktopCastControls> {
  final CastManager _manager = CastManager.instance;
  bool _owns = false;
  bool _busy = false;
  bool _dead = false;
  int _revision = 0;
  bool get ownsSession => _owns;

  @override
  void initState() { super.initState(); _manager.addListener(_changed); }
  @override
  void didUpdateWidget(DesktopCastControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_owns && oldWidget.streamUrl != widget.streamUrl) unawaited(_changeStream());
  }
  void _changed() {
    if (_dead || !mounted) return;
    if (_owns && !_busy && (_manager.state == CastState.idle || _manager.state == CastState.error)) {
      _owns = false;
      MediaKitVideoBackend.resumeAfterCast(widget.controller);
    }
    setState(() {});
  }
  Future<void> _changeStream() async {
    final device = _manager.device;
    if (device == null) return;
    final int ticket = ++_revision;
    _busy = true;
    try {
      await _manager.castTo(device, streamUrl: widget.streamUrl,
          title: widget.title, imageUrl: widget.imageUrl);
    } catch (_) {
      if (mounted && ticket == _revision) {
        _owns = false;
        MediaKitVideoBackend.resumeAfterCast(widget.controller);
      }
    } finally {
      if (mounted && ticket == _revision) { _busy = false; setState(() {}); }
    }
  }
  Future<void> _pick() async {
    if (_busy) return;
    final int ticket = ++_revision;
    setState(() => _busy = true);
    // Fermer le flux local avant le Cast évite de consommer deux connexions
    // chez les fournisseurs qui n’en autorisent qu’une. Le film garde sa position.
    try {
      await MediaKitVideoBackend.suspendForCast(widget.controller);
      if (!mounted || ticket != _revision) return;
      await showCastPicker(context, streamUrl: widget.streamUrl,
          title: widget.title, imageUrl: widget.imageUrl);
      if (!mounted || ticket != _revision) return;
      _owns = _manager.isCasting;
    } catch (_) {
      if (mounted && ticket == _revision) _owns = false;
    } finally {
      if (mounted && ticket == _revision) {
        if (!_owns) MediaKitVideoBackend.resumeAfterCast(widget.controller);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> togglePause() async {
    if (!_owns || _busy) return;
    setState(() => _busy = true);
    try {
      if (_manager.state == CastState.paused) { await _manager.resume(); }
      else { await _manager.pause(); }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _stop() async {
    if (_busy) return;
    ++_revision;
    setState(() { _busy = true; _owns = false; });
    await _manager.disconnect();
    if (!mounted) return;
    MediaKitVideoBackend.resumeAfterCast(widget.controller);
    setState(() => _busy = false);
  }
  @override
  void dispose() {
    _dead = true; ++_revision;
    _manager.removeListener(_changed);
    // Quitter le lecteur ne laisse jamais un relais orphelin derrière soi.
    if (_owns || _busy) unawaited(_manager.disconnect());
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (!CastPlatform.isWindows || !widget.streamUrl.startsWith(RegExp(r'https?://'))) return const SizedBox.shrink();
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
