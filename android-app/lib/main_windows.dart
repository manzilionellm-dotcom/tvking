import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
// =========================================================
//  main_windows.dart — Zuno sur PC (Windows)
// =========================================================
//  MÊME application que la box : même démarrage (bootstrapZunoTv), mêmes
//  écrans, même design, même panel (activation par MAC, licence, sources
//  poussées). Seules trois briques changent, parce qu'elles sont
//  Android-uniquement sur la box :
//
//    1. BASE DE DONNÉES : Windows n'a pas de SQLite système → moteur FFI
//       (sqflite_common_ffi) branché comme fabrique globale AVANT toute
//       ouverture de base.
//    2. LECTEUR : ExoPlayer n'existe pas sur PC → media_kit (libmpv,
//       décodage matériel) derrière le MÊME NativeVideoController.
//    3. FENÊTRE / CLAVIER : plein écran, Échap = Retour, F11 = plein écran.
//
//  Build : flutter build windows --release --target=lib/main_windows.dart
//  (workflow .github/workflows/build-zuno-windows.yml).
// =========================================================
import 'package:media_kit/media_kit.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app/guarded_main.dart';
import 'core/app/startup_trace.dart';
import 'features/cinema/data/cinema_repository.dart';
import 'features/tv/desktop/desktop_shell.dart';
import 'features/tv/desktop/desktop_startup.dart';
import 'features/tv/desktop/media_kit_video_backend.dart';
import 'main_tv.dart';

final ValueNotifier<DesktopStartupFailure?> _startupFailure =
    ValueNotifier<DesktopStartupFailure?>(null);
List<String> _args = const <String>[];
String? _smokeMarker;
bool _realUiStarted = false;

void main(List<String> args) {
  _args = args;
  if (args.length == 2 && args.first == '--zuno-smoke') {
    _smokeMarker = args.last;
    HttpOverrides.global = DesktopSmokeHttpOverrides();
  } else if (args.length == 2 && args.first == '--zuno-smoke-online') {
    // Même vérification, réseau RÉEL : le démarrage normal d'un PC client.
    _smokeMarker = args.last;
  }
  DesktopStartupLog.open(header: <String>[
    'exe=${Platform.resolvedExecutable}',
    'os=${Platform.operatingSystemVersion} locale=${Platform.localeName}',
    'smoke=${_smokeMarker == null ? 'non' : (HttpOverrides.current == null ? 'en ligne' : 'hors réseau')}',
  ]);
  StartupTrace.sink = DesktopStartupLog.write;
  // PC : aucune étape d'initialisation ne peut bloquer l'interface.
  StartupTrace.tolerant = true;
  runGuarded(
    _bootstrapWindows,
    startupWidget: DesktopStartupScreen(
      failure: _startupFailure,
      logPath: DesktopStartupLog.path,
      onRetry: _restart,
      onClose: _close,
    ),
    onStartupError: _onStartupError,
    onUnhandledError: DesktopStartupLog.error,
  );
}

void _onStartupError(Object error, StackTrace? stack) {
  DesktopStartupLog.error('DÉMARRAGE', error, stack);
  // Le vrai écran a déjà remplacé l'écran de démarrage : rien à afficher.
  if (_realUiStarted) return;
  String text = '${error.runtimeType}: $error';
  if (text.length > 600) text = '${text.substring(0, 600)}…';
  _startupFailure.value = DesktopStartupFailure(text);
  unawaited(DesktopWindow.leaveFullscreen());
  final String? marker = _smokeMarker;
  if (marker != null) {
    try {
      File(marker).writeAsStringSync('error');
    } catch (_) {}
  }
}

/// Réessayer = relancer proprement le processus (aucun état à moitié prêt).
Future<void> _restart() async {
  DesktopStartupLog.write('Réessayer demandé');
  try {
    await Process.start(Platform.resolvedExecutable, _args,
        mode: ProcessStartMode.detached);
  } catch (e, s) {
    DesktopStartupLog.error('Réessayer', e, s);
    return;
  }
  exit(0);
}

void _close() {
  DesktopStartupLog.write('Fermer demandé');
  exit(0);
}

Future<void> _bootstrapWindows() async {
  // 1) SQLite embarqué (avant toute ouverture de base).
  StartupTrace.bootSync('sqlite', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 2) Lecteur PC (libmpv) derrière le contrat du lecteur de la box.
  StartupTrace.bootSync('mediaKit', () {
    MediaKit.ensureInitialized();
    NativeVideoController.backendFactory = MediaKitVideoBackend.new;
  });

  // 2b) Préférences illisibles (fichier tronqué par une coupure ou une
  //     fermeture forcée) : shared_preferences_windows lève alors une
  //     FormatException à CHAQUE lecture → mises de côté, jamais bloquantes.
  await StartupTrace.soft('preferencesCheck', _setAsideUnreadablePreferences,
      timeout: const Duration(seconds: 3));

  // 3) Fenêtre plein écran « Zuno ». Jamais bloquant.
  await StartupTrace.soft('window', DesktopWindow.prepare,
      timeout: const Duration(seconds: 5));

  // Puis EXACTEMENT le démarrage de la box, avec les raccourcis PC autour.
  // Films / Séries : recherche sur 150 000 titres (un PC a la mémoire que
  // n'ont pas les box 1–2 Go ; même code que la box, seul ce plafond change).
  StartupTrace.bootSync('cinemaMemory', CinemaRepository.instance.useDesktopMemory);
  await bootstrapZunoTv(wrap: (app) {
    _realUiStarted = true;
    return DesktopShell(child: app);
  });
  // Attendre un cadre de la vraie UI, pas seulement le splash de secours.
  await WidgetsBinding.instance.endOfFrame;
  StartupTrace.mark('realUi.frame');
  final String? marker = _smokeMarker;
  if (marker != null) {
    await File(marker).writeAsString('ready');
  }
}

Future<void> _setAsideUnreadablePreferences() async {
  final Directory dir = await getApplicationSupportDirectory();
  final File prefs = File('${dir.path}${Platform.pathSeparator}shared_preferences.json');
  if (!prefs.existsSync()) return;
  try {
    final String text = prefs.readAsStringSync();
    if (text.isEmpty || jsonDecode(text) is Map) return;
  } catch (_) {}
  final String aside =
      '${prefs.path}.illisible-${DateTime.now().millisecondsSinceEpoch}';
  prefs.renameSync(aside);
  StartupTrace.mark('preferencesCheck.setAside (fichier illisible conservé à côté)');
}
