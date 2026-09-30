// =========================================================
//  voice_hotkey.dart — Bouton micro, où que l'on soit dans l'UI
// =========================================================
//  Écoute la touche micro de la télécommande. Si le direct ou le
//  lecteur est ouvert, la touche est ignorée (on renvoie false :
//  l'écran vidéo la reçoit, on ne la vole pas). Sinon on ouvre la
//  recherche et la reconnaissance.
//
//  Au démarrage, on récupère aussi une phrase que la box aurait
//  reconnue avant que l'écran existe (activité relais).
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tv/core/tv_activity.dart';
import '../../tv/presentation/tv_search_screen.dart';
import '../../tv/presentation/tv_shell.dart';
import '../data/voice_capture.dart';
import '../domain/voice_keys.dart';
import 'voice_navigation.dart';

class VoiceHotkey extends StatefulWidget {
  const VoiceHotkey({super.key, required this.child});

  final Widget child;

  @override
  State<VoiceHotkey> createState() => _VoiceHotkeyState();
}

class _VoiceHotkeyState extends State<VoiceHotkey> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    TvActivity.addListener(_onBusyCleared);
    VoiceNavigation.pushSearch = _push;
    VoiceCapture.install((String q) {
      VoiceNavigation.openSearch(query: q);
      // La même phrase est aussi gardée côté Android : on la retire
      // pour ne pas la rejouer au prochain démarrage.
      unawaited(VoiceCapture.takePending());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pullPending());
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    TvActivity.removeListener(_onBusyCleared);
    if (VoiceNavigation.pushSearch == _push) {
      VoiceNavigation.pushSearch = null;
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!VoiceKeys.isMicLogical(event.logicalKey)) return false;
    // Lecteur ou direct : on ne consomme pas la touche.
    if (TvActivity.isBusy) return false;
    if (event is! KeyDownEvent) return true; // répétition avalée
    VoiceNavigation.openSearch(autoListen: true);
    return true;
  }

  /// La lecture vient de se terminer et une phrase attendait.
  void _onBusyCleared() {
    if (TvActivity.isBusy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || TvActivity.isBusy) return;
      final String q = VoiceNavigation.takePending();
      if (q.isEmpty) return;
      VoiceNavigation.openSearch(query: q);
    });
  }

  Future<void> _pullPending() async {
    final String? q = await VoiceCapture.takePending();
    if (!mounted || q == null) return;
    VoiceNavigation.openSearch(query: q);
  }

  void _push(String query, {required bool autoListen}) {
    final NavigatorState? nav = VoiceNavigation.navigatorKey.currentState;
    if (nav == null) {
      if (query.isNotEmpty) VoiceNavigation.stash(query);
      return;
    }
    nav.push(MaterialPageRoute<void>(
      builder: (_) => TvShell(
        child: TvSearchScreen(initialQuery: query, autoListen: autoListen),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
