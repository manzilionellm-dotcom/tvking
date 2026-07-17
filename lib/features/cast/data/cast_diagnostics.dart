// =========================================================
//  cast_diagnostics.dart — Batch runner pour la matrice compat
// =========================================================
//  Le testeur sélectionne UN récepteur + un preset (Rapide /
//  Standard / Complet) → on lance castTo sur N chaînes choisies
//  pour couvrir un maximum de variétés (genres + qualités), on
//  archive les diagnostics, on aggrège un rapport JSON.
//
//  Pas de framework de test — juste un Stopwatch, un for-loop
//  et un ChangeNotifier. L'écran s'abonne pour rafraîchir la
//  liste des résultats en live.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/observability/black_box.dart';
import '../../channels/domain/channel.dart';
import '../domain/cast_device.dart';
import 'cast_manager.dart';
import 'cast_url_resolver.dart';
import 'cast_session_diagnostic.dart';

/// Commit Git injecte au build via --dart-define=GIT_SHA=... (CI).
/// Vide en dev local. Permet de prouver quel commit tourne dans un rapport.
const String kBuildCommit =
    String.fromEnvironment('GIT_SHA', defaultValue: 'local');

enum DiagnosticPreset {
  quick(label: 'Rapide', sampleSize: 3, description: '3 chaînes (~1 min)'),
  standard(label: 'Standard', sampleSize: 8, description: '8 chaînes (~3 min)'),
  thorough(
    label: 'Complet',
    sampleSize: 15,
    description: '15 chaînes (~6 min)',
  );

  const DiagnosticPreset({
    required this.label,
    required this.sampleSize,
    required this.description,
  });

  final String label;
  final int sampleSize;
  final String description;
}

/// Sélection équilibrée de chaînes pour le diagnostic. On répartit
/// par genre via un round-robin pour maximiser la diversité du test
/// (un Sport + un Film + un Info + un Kids + un Doc...). Sur un
/// catalogue où 90% des chaînes sont du sport, on aurait sinon 8
/// sports identiques et zéro info sur le report.
List<Channel> pickDiagnosticChannels(List<Channel> all, int sampleSize) {
  if (all.isEmpty) return const <Channel>[];

  // Groupe par genre
  final Map<String, List<Channel>> byGenre = <String, List<Channel>>{};
  for (final Channel ch in all) {
    byGenre.putIfAbsent(ch.genre.label, () => <Channel>[]).add(ch);
  }

  // Round-robin
  final List<Channel> result = <Channel>[];
  final List<List<Channel>> buckets =
      byGenre.values.toList(growable: false);
  bool addedAny = true;
  while (result.length < sampleSize && addedAny) {
    addedAny = false;
    for (final List<Channel> bucket in buckets) {
      if (result.length >= sampleSize) break;
      if (bucket.isNotEmpty) {
        result.add(bucket.removeAt(0));
        addedAny = true;
      }
    }
  }
  return result;
}

/// Coordonne une série de tests cast contre UN récepteur. Notifie
/// ses listeners à chaque transition pour que l'UI suive en direct.
class DiagnosticBatchRunner extends ChangeNotifier {
  DiagnosticBatchRunner({
    required this.device,
    required this.channels,
  });

  final CastDevice device;
  final List<Channel> channels;

  bool _running = false;
  bool _cancelled = false;
  int _currentIndex = 0;
  final List<CastSessionDiagnostic> _results = <CastSessionDiagnostic>[];

  bool get isRunning => _running;
  bool get isCancelled => _cancelled;
  int get currentIndex => _currentIndex;
  int get totalCount => channels.length;
  List<CastSessionDiagnostic> get results =>
      List<CastSessionDiagnostic>.unmodifiable(_results);

  /// Nom de la chaîne actuellement en test — pour l'UI "Test 3/8 : NRJ12".
  String? get currentChannelName {
    if (!_running || _currentIndex >= channels.length) return null;
    return channels[_currentIndex].name;
  }

  /// Délai entre 2 tests pour laisser le récepteur revenir à STOPPED
  /// proprement. Trop court → certains Sony renvoient 500 sur le test
  /// suivant. 2s suffit dans 99% des cas.
  static const Duration _kInterTestPause = Duration(seconds: 2);

  Future<void> run() async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    _results.clear();
    _currentIndex = 0;
    notifyListeners();

    try {
      for (int i = 0; i < channels.length; i++) {
        if (_cancelled) break;
        _currentIndex = i;
        notifyListeners();

        final Channel ch = channels[i];
        final DateTime iterationStart = DateTime.now();

        // 1) Cast — on encaisse l'exception, le diagnostic est déjà
        //    archivé par le CastManager dans tous les cas (finally).
        try {
          // Même résolution d'URL que playChannel (format Xtream
          // mémorisé) : le testeur doit refléter le vrai chemin de cast,
          // pas échouer sur la forme brute d'un panel « /live/ requis ».
          final String castUrl = await CastUrlResolver.resolve(ch);
          await CastManager.instance.castTo(
            device,
            streamUrl: castUrl,
            title: ch.name,
            channelName: ch.name,
            channelGenre: ch.genre.label,
          );
        } on Exception {
          // Pas d'action — l'erreur est enregistrée dans le diag.
        }

        // 2) Ramasser le diagnostic qui vient d'être archivé.
        //    GARDE ANTI-DOUBLON (terrain 2026-07-17, rapport LG avec
        //    sessions dupliquées) : quand castTo échoue par TIMEOUT
        //    GLOBAL, il lève AVANT que la session inner n'ait archivé
        //    son diagnostic (le finally de _castToInner ne s'exécute
        //    qu'à sa complétion coopérative, parfois ~15 s plus tard,
        //    un SOAP encore en vol). À cet instant, recent.first est
        //    encore le diag de l'itération PRÉCÉDENTE → il était
        //    ré-ajouté tel quel. On ne ramasse que si le diagnostic
        //    date bien de CETTE itération.
        final List<CastSessionDiagnostic> recent =
            CastManager.instance.recentDiagnostics;
        if (recent.isNotEmpty &&
            !recent.first.startedAt.isBefore(iterationStart)) {
          // Le 1er = celui qu'on vient d'archiver (insert à 0)
          _results.add(recent.first);
          notifyListeners();
        }

        // 3) Disconnect + pause entre tests.
        try {
          await CastManager.instance.disconnect();
        } on Exception catch (e) {
          if (kDebugMode) debugPrint('[Diag] disconnect: $e');
        }

        if (i + 1 < channels.length && !_cancelled) {
          await Future<void>.delayed(_kInterTestPause);
        }
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    // On laisse l'itération courante finir naturellement (castTo +
    // disconnect) avant de sortir — éviter d'arracher la connexion
    // au récepteur.
  }

  // -------- Agrégats pour l'UI résumé --------

  int get successCount => _results.where((CastSessionDiagnostic d) => d.success).length;
  int get failureCount => _results.length - successCount;

  /// Distribution des stratégies gagnantes : `{ 'relay+full': 5, 'direct+full': 2 }`.
  /// Permet à l'UI de dire "ta TV nécessite la relay dans 80% des cas".
  Map<String, int> get winningStrategyCounts {
    final Map<String, int> out = <String, int>{};
    for (final CastSessionDiagnostic d in _results) {
      final AttemptResult? win = d.winningAttempt;
      if (win != null) {
        out[win.strategyName] = (out[win.strategyName] ?? 0) + 1;
      }
    }
    return out;
  }

  /// Latence moyenne (ms) sur les tests réussis. `null` si aucun
  /// succès — l'UI affichera "—".
  int? get averageSuccessLatencyMs {
    final List<int> latencies = <int>[];
    for (final CastSessionDiagnostic d in _results) {
      if (d.success && d.totalDurationMs != null) {
        latencies.add(d.totalDurationMs!);
      }
    }
    if (latencies.isEmpty) return null;
    final int sum = latencies.reduce((int a, int b) => a + b);
    return sum ~/ latencies.length;
  }

  // -------- Export JSON --------

  /// Rapport JSON formaté + lisible. C'est ce qui se copie dans le
  /// presse-papier puis dans une issue GitHub / le matrice doc.
  String exportReport() {
    final Map<String, dynamic> report = <String, dynamic>{
      'meta': <String, dynamic>{
        'generatedAt': DateTime.now().toIso8601String(),
        'app': '7 MOTION',
        'buildCommit': kBuildCommit,
        'device': <String, dynamic>{
          'name': device.name,
          'kind': device.kind.name,
          'host': device.host,
          if (device.manufacturer != null)
            'manufacturer': device.manufacturer,
          if (device.model != null) 'model': device.model,
        },
        'sampleSize': _results.length,
        'plannedSize': channels.length,
        'cancelled': _cancelled,
        'successCount': successCount,
        'failureCount': failureCount,
        'successRate':
            _results.isEmpty ? 0.0 : successCount / _results.length,
        'averageSuccessLatencyMs': averageSuccessLatencyMs,
        'winningStrategies': winningStrategyCounts,
      },
      // Constats de la BOÎTE NOIRE au moment de l'export : le rapport
      // colle en un bloc les échecs de cast ET l'état général de l'app
      // (proxy bloqué, crashs, relais mort…) — plus besoin de croiser
      // deux exports pour diagnostiquer.
      'blackBox': BlackBox.instance
          .analyze()
          .map((BlackBoxFinding f) => f.toString())
          .toList(growable: false),
      'sessions': _results
          .map((CastSessionDiagnostic d) => d.toJson())
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }
}
