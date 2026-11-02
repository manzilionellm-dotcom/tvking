import 'dart:async';

import 'package:flutter/material.dart';

import '../../cast/data/cast_manager.dart';
import '../../tv/core/tv_app_tokens.dart';
import '../data/startup_ad_repository.dart';
import 'tv_startup_ad_screen.dart';

/// La vidéo du panel est une porte d'entrée, jamais une interruption du direct.
/// Une réponse arrivée après le délai d'ouverture est ignorée pour cette session.
class TvStartupAdGate extends StatefulWidget {
  const TvStartupAdGate({super.key, required this.child, this.castManager});
  final Widget child;
  @visibleForTesting
  final CastManager? castManager;

  @override
  State<TvStartupAdGate> createState() => _TvStartupAdGateState();
}

class _TvStartupAdGateState extends State<TvStartupAdGate>
    with WidgetsBindingObserver {
  late final CastManager _cast;
  Timer? _deadline;
  AdConfig? _ad;
  bool _resolved = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cast = widget.castManager ?? CastManager.instance;
    _cast.addListener(_onCast);
    if (_cast.hasActiveSession) {
      _resolved = _done = true;
      return;
    }
    _deadline = Timer(const Duration(milliseconds: 2500), _finish);
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final StartupAdRepository repo = StartupAdRepository.instance;
    final AdConfig config = await repo.fetch();
    final bool show = await repo.shouldShow();
    if (!mounted || _done || _resolved) return;
    _deadline?.cancel();
    setState(() {
      _resolved = true;
      _ad = show && !_cast.hasActiveSession ? config : null;
    });
  }

  void _onCast() {
    if (_cast.hasActiveSession) _finish();
  }

  void _finish() {
    _deadline?.cancel();
    if (!mounted || _done) return;
    setState(() {
      _resolved = true;
      _done = true;
      _ad = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Aucune pub poursuivie en arrière-plan ni relancée au retour du PiP.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _finish();
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _cast.removeListener(_onCast);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return ColoredBox(
        color: TvAppTokens.of(context).bg,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final AdConfig? ad = _ad;
    if (!_done && ad != null) {
      return TvStartupAdScreen(config: ad, onDone: _finish);
    }
    return widget.child;
  }
}
