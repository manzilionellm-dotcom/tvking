// =========================================================
//  black_box.dart — BOÎTE NOIRE (enregistreur de vol de l'application)
// =========================================================
//  Décision du propriétaire (25/09/2026) : quand l'app se ferme toute seule,
//  on doit pouvoir lire EXACTEMENT pourquoi, depuis la télé, sans ordinateur.
//
//  Ce que fait cette classe (et rien d'autre que consigner) :
//    • JOURNAL SUR DISQUE, écrit de façon SYNCHRONE avec flush immédiat : une
//      mort brutale du process (kill mémoire, plantage natif) ne perd pas la
//      dernière ligne. Fichier tournant : `blackbox.log` (≤ 512 Ko) puis
//      `blackbox.1.log` (génération précédente). Jamais plus de ~1 Mo.
//    • FIL D'ARIANE (`breadcrumb`) : la « dernière action en cours », écrite
//      dans un petit fichier séparé → au redémarrage suivant on sait ce que
//      l'app faisait quand elle est morte (ex. « import Xtream S1, 31 Mo »).
//    • SESSION : marqueur « sortie propre » posé quand l'app passe en arrière-
//      plan ou se ferme normalement ; absent au boot suivant = FERMETURE BRUTALE.
//    • RAISON NATIVE (Android 11+) : `getLastExitInfo` du plugin tvking_device
//      (ActivityManager.getHistoricalProcessExitReasons) → LOW_MEMORY / ANR /
//      CRASH_NATIVE… + mémoire au moment de la mort. C'est la preuve.
//    • MÉMOIRE : échantillon toutes les 30 s (PSS du process, RAM dispo, seuil
//      « mémoire basse » d'Android) + à la demande autour des étapes lourdes.
//    • GELS DU FIL UI : chien de garde qui mesure la dérive d'un Timer 500 ms
//      → tout blocage > 700 ms est consigné avec l'action en cours. C'est
//      précisément ce qui précède un ANR (Android tue à ~5 s).
//    • ERREURS : tout ce que `CrashReporting` rattrape passe aussi ici.
//
//  Coût : négligeable (quelques écritures de 100 octets par minute en usage
//  normal). Aucune dépendance ajoutée : path_provider + dart:io + le plugin
//  local tvking_device. Aucun élément visuel : l'écran de lecture est à part
//  (features/tv/presentation/tv_black_box_screen.dart).
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Niveau d'une ligne du journal.
enum BbLevel { info, warn, error, fatal }

/// Résumé de la dernière session, calculé au démarrage.
class BlackBoxLastExit {
  const BlackBoxLastExit({
    required this.brutal,
    required this.at,
    required this.lastAction,
    required this.nativeReason,
    required this.nativeDescription,
    required this.pssMb,
    required this.rssMb,
  });

  /// Vrai si la session précédente ne s'est PAS terminée proprement.
  final bool brutal;

  /// Date approximative de la fin de la session précédente.
  final DateTime? at;

  /// Dernier fil d'Ariane écrit avant la mort.
  final String lastAction;

  /// Raison Android (API 30+), ex. « LOW_MEMORY (tuée : mémoire insuffisante) ».
  final String nativeReason;
  final String nativeDescription;
  final int pssMb;
  final int rssMb;

  String get headline {
    if (!brutal) return 'Dernière session terminée normalement.';
    final String r = nativeReason.isEmpty ? 'raison inconnue (Android < 11)' : nativeReason;
    final String mem = pssMb > 0 ? ' · mémoire $pssMb Mo' : '';
    return 'FERMETURE BRUTALE · $r$mem';
  }
}

class BlackBox {
  BlackBox._();
  static final BlackBox instance = BlackBox._();

  static const MethodChannel _device =
      MethodChannel('com.manzilionellm.tvking/device');

  static const int _kMaxBytes = 512 * 1024;
  static const Duration _kMemoryEvery = Duration(seconds: 30);
  static const Duration _kWatchdogTick = Duration(milliseconds: 500);
  static const Duration _kStallThreshold = Duration(milliseconds: 700);

  Directory? _dir;
  RandomAccessFile? _file;
  int _size = 0;
  bool _ready = false;
  String _breadcrumb = '';
  BlackBoxLastExit? _lastExit;
  Timer? _memTimer;
  Timer? _watchdog;
  DateTime _lastTick = DateTime.now();
  AppLifecycleListener? _lifecycle;
  String _appVersion = '?';

  bool get isReady => _ready;
  BlackBoxLastExit? get lastExit => _lastExit;
  String get appVersion => _appVersion;

  /// Chemin du journal courant (pour l'écran de lecture).
  File? get logFile => _dir == null ? null : File('${_dir!.path}/blackbox.log');
  File? get _prevFile => _dir == null ? null : File('${_dir!.path}/blackbox.1.log');
  File? get _crumbFile => _dir == null ? null : File('${_dir!.path}/blackbox.last_action');
  File? get _sessionFile => _dir == null ? null : File('${_dir!.path}/blackbox.session');

  // ---------------------------------------------------------------------
  //  Démarrage
  // ---------------------------------------------------------------------

  /// À appeler UNE fois, tôt au boot (après `ensureInitialized`). Ne throw
  /// jamais : sans disque, la boîte noire se tait et l'app démarre quand même.
  Future<void> initialize({required String flavor}) async {
    if (_ready) return;
    try {
      _dir = await getApplicationSupportDirectory();
      await _rotateIfNeeded();
      _file = await logFile!.open(mode: FileMode.append);
      _size = await logFile!.length();
      _ready = true;
    } catch (e) {
      debugPrint('[BlackBox] disque indisponible : $e');
      return;
    }

    // 1) Analyse de la session PRÉCÉDENTE (avant d'écrire quoi que ce soit).
    _lastExit = await _analysePreviousSession();

    // 2) Nouvelle session : marqueur « pas encore sortie proprement ».
    _writeSession(clean: false);
    _breadcrumb = '';
    try {
      final PackageInfo p = await PackageInfo.fromPlatform();
      _appVersion = '${p.version}+${p.buildNumber}';
    } catch (_) {}

    _line(BbLevel.info, 'BOOT',
        '===== démarrage $flavor v$_appVersion =====');
    if (_lastExit != null) {
      final BlackBoxLastExit x = _lastExit!;
      _line(x.brutal ? BbLevel.fatal : BbLevel.info, 'EXIT',
          'session précédente : ${x.headline}'
          '${x.lastAction.isEmpty ? '' : ' · dernière action : ${x.lastAction}'}'
          '${x.nativeDescription.isEmpty ? '' : ' · ${x.nativeDescription}'}');
    }
    await _logDevice();
    await logMemory('boot');

    // 3) Sondes continues.
    _memTimer = Timer.periodic(_kMemoryEvery, (_) => logMemory('périodique'));
    _lastTick = DateTime.now();
    _watchdog = Timer.periodic(_kWatchdogTick, _onWatchdogTick);

    // 4) Cycle de vie : sortie propre / retour.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _line(BbLevel.info, 'APP', 'arrière-plan');
        _writeSession(clean: true);
      },
      onResume: () {
        _line(BbLevel.info, 'APP', 'premier plan');
        _writeSession(clean: false);
      },
      onDetach: () {
        _line(BbLevel.info, 'APP', 'fermeture normale');
        _writeSession(clean: true);
      },
    );
  }

  Future<BlackBoxLastExit?> _analysePreviousSession() async {
    bool hadSession = false;
    bool clean = true;
    DateTime? at;
    try {
      final File? f = _sessionFile;
      if (f != null && await f.exists()) {
        hadSession = true;
        final Map<String, dynamic> j =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        clean = j['clean'] == true;
        final int ts = (j['at'] as num?)?.toInt() ?? 0;
        if (ts > 0) at = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    } catch (_) {}
    if (!hadSession) return null; // tout premier lancement

    String lastAction = '';
    try {
      final File? c = _crumbFile;
      if (c != null && await c.exists()) lastAction = (await c.readAsString()).trim();
    } catch (_) {}

    String reason = '';
    String desc = '';
    int pss = 0;
    int rss = 0;
    try {
      final Object? raw = await _device.invokeMethod<Object?>('getLastExitInfo');
      if (raw is List && raw.isNotEmpty) {
        // La plus récente en premier (ordre Android).
        final Map<Object?, Object?> m = raw.first as Map<Object?, Object?>;
        reason = (m['reasonName'] ?? '').toString();
        desc = (m['description'] ?? '').toString();
        pss = (m['pssMb'] as num?)?.toInt() ?? 0;
        rss = (m['rssMb'] as num?)?.toInt() ?? 0;
        final int ts = (m['timestamp'] as num?)?.toInt() ?? 0;
        if (ts > 0) at = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    } catch (_) {}

    return BlackBoxLastExit(
      brutal: !clean,
      at: at,
      lastAction: lastAction,
      nativeReason: reason,
      nativeDescription: desc,
      pssMb: pss,
      rssMb: rss,
    );
  }

  Future<void> _logDevice() async {
    try {
      final Object? d = await _device.invokeMethod<Object?>('getDeviceInfo');
      final Object? m = await _device.invokeMethod<Object?>('getMemoryInfo');
      if (d is Map) {
        _line(BbLevel.info, 'DEVICE',
            '${d['manufacturer']} ${d['model']} · Android ${d['release']} (API ${d['sdk']})'
            '${m is Map ? ' · RAM ${m['totalMb']} Mo${m['lowRam'] == true ? ' (low RAM)' : ''}' : ''}');
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  //  API publique de consignation
  // ---------------------------------------------------------------------

  /// Ligne d'information (écran ouvert, import terminé, zap…).
  void info(String tag, String message) => _line(BbLevel.info, tag, message);

  void warn(String tag, String message) => _line(BbLevel.warn, tag, message);

  void error(String tag, String message, [Object? err]) =>
      _line(BbLevel.error, tag, err == null ? message : '$message : $err');

  /// « Action en cours » : écrite aussi dans un fichier séparé pour survivre
  /// à une mort brutale. Passer une chaîne vide quand l'action est finie.
  void breadcrumb(String action) {
    _breadcrumb = action;
    try {
      _crumbFile?.writeAsStringSync(action, flush: true);
    } catch (_) {}
    if (action.isNotEmpty) _line(BbLevel.info, 'ACTION', action);
  }

  /// Échantillon mémoire (PSS process, RAM dispo, seuil système).
  Future<void> logMemory(String context) async {
    if (!_ready) return;
    try {
      final Object? raw = await _device.invokeMethod<Object?>('getProcessMemory');
      final int rss = ProcessInfo.currentRss ~/ (1024 * 1024);
      if (raw is Map) {
        final bool low = raw['lowMemory'] == true;
        _line(low ? BbLevel.warn : BbLevel.info, 'MEM',
            '[$context] process ${raw['pssMb']} Mo (rss $rss, natif ${raw['nativeHeapMb']}) · '
            'dispo ${raw['availMb']}/${raw['totalMb']} Mo · seuil ${raw['thresholdMb']} Mo'
            '${low ? ' · MÉMOIRE BASSE (Android va tuer des apps)' : ''}');
      } else {
        _line(BbLevel.info, 'MEM', '[$context] rss $rss Mo');
      }
    } catch (_) {}
  }

  /// Chien de garde : un Timer de 500 ms qui arrive avec > 700 ms de retard
  /// signifie que le fil UI a été BLOQUÉ pendant ce temps.
  void _onWatchdogTick(Timer _) {
    final DateTime now = DateTime.now();
    final Duration late = now.difference(_lastTick) - _kWatchdogTick;
    _lastTick = now;
    if (late > _kStallThreshold) {
      _line(late.inMilliseconds >= 3000 ? BbLevel.error : BbLevel.warn, 'GEL',
          'fil UI bloqué ~${late.inMilliseconds} ms'
          '${_breadcrumb.isEmpty ? '' : ' pendant : $_breadcrumb'}');
    }
  }

  // ---------------------------------------------------------------------
  //  Lecture (écran Boîte noire)
  // ---------------------------------------------------------------------

  /// Les [max] dernières lignes (journal précédent + courant), plus récentes
  /// en fin de liste.
  Future<List<String>> tail({int max = 400}) async {
    if (!_ready) return const <String>['(boîte noire indisponible : disque)'];
    final List<String> out = <String>[];
    try {
      final File? prev = _prevFile;
      if (prev != null && await prev.exists()) {
        out.addAll(const LineSplitter().convert(await prev.readAsString()));
      }
      final File? cur = logFile;
      if (cur != null && await cur.exists()) {
        out.addAll(const LineSplitter().convert(await cur.readAsString()));
      }
    } catch (e) {
      out.add('(lecture impossible : $e)');
    }
    return out.length > max ? out.sublist(out.length - max) : out;
  }

  /// Vide le journal (garde la session courante ouverte).
  Future<void> clear() async {
    if (!_ready) return;
    try {
      await _file?.close();
      final File? prev = _prevFile;
      if (prev != null && await prev.exists()) await prev.delete();
      await logFile?.writeAsString('');
      _file = await logFile!.open(mode: FileMode.append);
      _size = 0;
      _line(BbLevel.info, 'BOX', 'journal effacé par l\'utilisateur');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  //  Internes
  // ---------------------------------------------------------------------

  void _line(BbLevel level, String tag, String message) {
    final DateTime t = DateTime.now();
    final String hh = t.hour.toString().padLeft(2, '0');
    final String mm = t.minute.toString().padLeft(2, '0');
    final String ss = t.second.toString().padLeft(2, '0');
    final String d = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
    final String lv = switch (level) {
      BbLevel.info => 'I',
      BbLevel.warn => 'W',
      BbLevel.error => 'E',
      BbLevel.fatal => 'F',
    };
    final String text = '$d $hh:$mm:$ss $lv [$tag] ${message.replaceAll('\n', ' ')}\n';
    if (kDebugMode) debugPrint('[BlackBox] $text');
    if (!_ready || _file == null) return;
    try {
      // SYNCHRONE + flush : si le process meurt juste après, la ligne est là.
      _file!.writeStringSync(text);
      _file!.flushSync();
      _size += text.length;
      if (_size > _kMaxBytes) {
        _file!.closeSync();
        _file = null;
        _rotateNow();
        _file = logFile!.openSync(mode: FileMode.append);
        _size = 0;
      }
    } catch (_) {}
  }

  void _writeSession({required bool clean}) {
    try {
      _sessionFile?.writeAsStringSync(
        jsonEncode(<String, Object>{
          'clean': clean,
          'at': DateTime.now().millisecondsSinceEpoch,
          'version': _appVersion,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _rotateIfNeeded() async {
    final File f = logFile!;
    if (await f.exists() && await f.length() > _kMaxBytes) _rotateNow();
  }

  void _rotateNow() {
    try {
      final File cur = logFile!;
      final File prev = _prevFile!;
      if (prev.existsSync()) prev.deleteSync();
      if (cur.existsSync()) cur.renameSync(prev.path);
    } catch (_) {}
  }
}
