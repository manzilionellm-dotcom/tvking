import 'dart:async';

import 'package:flutter/material.dart';

import '../../cast/data/cast_manager.dart';
import '../../tv/core/tv_activity.dart';
import '../data/startup_ad_repository.dart';
import 'tv_startup_ad_screen.dart';

/// La vidéo du panel est une porte d'entrée, jamais une interruption
/// d'une chaîne déjà ouverte.
///
/// L'accueil s'affiche tout de suite : on n'attend plus le réseau derrière
/// un écran vide (le délai de 2,5 s ne servait qu'à ça). Si la réponse
/// de CE démarrage arrive avant la fin du délai, la pub passe devant.
/// Après, seule une nouvelle lecture (ordre `ad` du panel) la réaffiche,
/// et seulement quand aucun écran lourd n'est ouvert.
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

  /// Vrai une fois la lecture de démarrage terminée. Les révisions
  /// d'avant ne sont pas des ordres du panel.
  bool _pushArmed = false;
  bool _queuedPush = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cast = widget.castManager ?? CastManager.instance;
    _cast.addListener(_onCast);
    StartupAdRepository.instance.revision.addListener(_onRevision);
    TvActivity.addListener(_onActivity);
    if (_cast.hasActiveSession) {
      _resolved = _done = true;
      _pushArmed = true;
      return;
    }
    _deadline = Timer(const Duration(milliseconds: 2500), _expireStartup);
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final StartupAdRepository repo = StartupAdRepository.instance;
    final bool cached = await repo.warmFromCache();
    if (!mounted) return;
    if (!_done &&
        cached &&
        await repo.shouldShow() &&
        !_cast.hasActiveSession &&
        !TvActivity.isBusy) {
      _deadline?.cancel();
      setState(() {
        _resolved = true;
        _ad = repo.config;
      });
    }
    await repo.fetch();
    if (!mounted) return;
    // La révision de cette lecture a déjà été émise. On arme après,
    // pour ne pas la prendre pour un ordre arrivé pendant l'ouverture.
    _pushArmed = true;
    if (_done) return;
    // Cache déjà à l'écran : on ne relance pas la même vidéo.
    // Une autre adresse publiée entre-temps remplace celle du cache.
    if (_ad != null) {
      if (repo.config.url != _ad!.url &&
          await repo.shouldShow() &&
          !TvActivity.isBusy) {
        if (!mounted) return;
        setState(() => _ad = repo.config);
      }
      return;
    }
    final bool show = await repo.shouldShow();
    if (!mounted || _done) return;
    _deadline?.cancel();
    final bool cover =
        show && !_cast.hasActiveSession && !TvActivity.isBusy;
    setState(() {
      _resolved = true;
      _ad = cover ? repo.config : null;
      if (!cover) _done = true;
    });
  }

  void _onRevision() {
    if (!_pushArmed) return;
    unawaited(_presentPush());
  }

  void _onActivity() {
    if (_queuedPush && !TvActivity.isBusy) {
      unawaited(_presentPush());
    }
  }

  /// Ordre `ad` reçu pendant que l'app tourne. On ne couvre pas le
  /// direct : la pub attend le retour à l'accueil.
  Future<void> _presentPush() async {
    if (!_pushArmed || !mounted) return;
    if (_cast.hasActiveSession) return;
    if (TvActivity.isBusy) {
      _queuedPush = true;
      return;
    }
    _queuedPush = false;
    final StartupAdRepository repo = StartupAdRepository.instance;
    final bool show = await repo.shouldShow();
    if (!mounted || !_pushArmed || !show || _cast.hasActiveSession) return;
    if (TvActivity.isBusy) {
      _queuedPush = true;
      return;
    }
    final AdConfig config = repo.config;
    if (!_done && _ad?.url == config.url && _ad?.skip == config.skip) return;
    setState(() {
      _resolved = true;
      _done = false;
      _ad = config;
    });
  }

  void _onCast() {
    if (_cast.hasActiveSession) _finish();
  }

  /// Le délai d'ouverture est passé et aucune pub n'est à l'écran :
  /// la réponse tardive de CE démarrage ne recouvre pas l'accueil.
  void _expireStartup() {
    if (!mounted || _done || _ad != null) return;
    setState(() {
      _resolved = true;
      _done = true;
      _ad = null;
    });
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
    StartupAdRepository.instance.revision.removeListener(_onRevision);
    TvActivity.removeListener(_onActivity);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pas d'écran vide : l'accueil est là pendant la lecture réseau.
    // La pub, si elle gagne le délai, le remplace.
    if (!_resolved) return widget.child;
    final AdConfig? ad = _ad;
    if (!_done && ad != null) {
      return TvStartupAdScreen(config: ad, onDone: _finish);
    }
    return widget.child;
  }
}
