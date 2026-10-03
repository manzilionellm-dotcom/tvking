// =========================================================
//  audio_sources_bind.dart — Branche le compteur, sans couper
// =========================================================
//  Au démarrage : le plugin prévient [AudioSources] à chaque
//  lecteur, et un observateur PHOTOGRAPHIE qui a encore du son
//  quand l'app passe en arrière-plan. Il n'appelle ni pause, ni
//  stop, ni abandon de focus.
// =========================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/blackbox/black_box.dart';
import '../domain/audio_sources.dart';
import 'audio_report_store.dart';

/// À appeler une fois, après les bindings Flutter, avant le premier
/// lecteur. Deux appels ne posent pas deux observateurs.
void bindAudioSources() {
  NativeVideoController.sourceHook = AudioSources.onPlayerEvent;
  AudioSources.controllerCount =
      () => NativeVideoController.audiblePlayers.registeredCount;
  AudioSources.onChange = _remember;
  _AudioSourceWatch.install();
}

void _remember(String line) {
  // La boîte noire (si elle est prête) et la fiche « (sources) ».
  // La ligne ne contient pas d'adresse : que des comptes.
  BlackBox.instance.info('SON', line);
  unawaited(AudioReportStore.instance.record(channel: '(sources)', body: line));
}

class _AudioSourceWatch with WidgetsBindingObserver {
  static final _AudioSourceWatch _instance = _AudioSourceWatch();
  static bool _installed = false;
  bool _away = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(_instance);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // hidden suit paused : une seule photo par départ.
        if (_away) return;
        _away = true;
        AudioSources.markHome();
        break;
      case AppLifecycleState.resumed:
        _away = false;
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }
}
