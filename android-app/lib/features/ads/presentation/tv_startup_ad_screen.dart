import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_app_tokens.dart';
import '../data/startup_ad_repository.dart';

/// Même moteur natif que Zuno : ne charge pas media_kit sur une box TV.
/// Le décompte commence à la première image, pas pendant le téléchargement.
class TvStartupAdScreen extends StatefulWidget {
  const TvStartupAdScreen({
    super.key,
    required this.config,
    required this.onDone,
  });
  final AdConfig config;
  final VoidCallback onDone;

  @override
  State<TvStartupAdScreen> createState() => _TvStartupAdScreenState();
}

class _TvStartupAdScreenState extends State<TvStartupAdScreen> {
  late final NativeVideoController _player;
  Timer? _startupTimeout;
  Timer? _skipTimer;
  Timer? _safetyTimer;
  bool _started = false;
  bool _canSkip = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _player = NativeVideoController(
      initialUrl: widget.config.url,
      openAsVod: true,
    );
    _player.addListener(_onPlayer);
    _startupTimeout = Timer(const Duration(seconds: 12), _finish);
    // Un flux publicitaire accidentellement infini reste toujours quittable.
    _safetyTimer = Timer(const Duration(seconds: 120), _finish);
  }

  void _onPlayer() {
    if (_done || !mounted) return;
    if (_player.hasError || _player.isEnded) {
      _finish();
      return;
    }
    if (!_started && _player.firstFrame) {
      _started = true;
      _startupTimeout?.cancel();
      unawaited(StartupAdRepository.instance.markShown());
      _skipTimer = Timer(Duration(seconds: widget.config.skip), () {
        if (mounted && !_done) setState(() => _canSkip = true);
      });
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    _player.pause();
    widget.onDone();
  }

  @override
  void dispose() {
    _startupTimeout?.cancel();
    _skipTimer?.cancel();
    _safetyTimer?.cancel();
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (bool didPop, Object? _) {
      if (!didPop) _finish();
    },
    child: Scaffold(
      backgroundColor: TvAppTokens.of(context).bg,
      body: Stack(
        children: <Widget>[
          // La vidéo ne prend pas le focus : sinon le D-pad le lui donnait
          // (avant « Passer », ou Gauche/Bas depuis lui) et OK ne passait
          // plus la pub.
          Positioned.fill(
            child: ExcludeFocus(child: NativeVideoView(controller: _player)),
          ),
          Positioned(
            top: TvDimens.safeV,
            left: TvDimens.safeH,
            child: Material(
              color: TvAppTokens.of(context).card,
              child: Padding(
                padding: const EdgeInsets.all(TvDimens.rowGap),
                child: Text(
                  context.l10n.tvAdvertisement,
                  style: TvAppTokens.of(context).ui(TvDimens.label),
                ),
              ),
            ),
          ),
          if (_canSkip)
            Positioned(
              top: TvDimens.safeV,
              right: TvDimens.safeH,
              child: FilledButton.icon(
                autofocus: true,
                onPressed: _finish,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(context.l10n.buttonSkip),
              ),
            ),
        ],
      ),
    ),
  );
}
