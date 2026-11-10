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

import '../../channels/domain/adult_channel_policy.dart';
import '../../channels/domain/channel.dart';
import '../../profiles/data/active_profile.dart';
import '../../tv/core/tv_activity.dart';
import '../domain/cast_device.dart';
import 'cast_manager.dart';
import 'cast_session_diagnostic.dart';

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
    if (!_diagnosticChannelAllowed(ch)) continue;
    byGenre.putIfAbsent(ch.genre.label, () => <Channel>[]).add(ch);
  }

  // Round-robin
  final List<Channel> result = <Channel>[];
  final List<List<Channel>> buckets = byGenre.values.toList(growable: false);
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

bool _diagnosticChannelAllowed(Channel channel) =>
    ActiveProfile.instance.allowsPlaylist(channel.playlistId) &&
    !isAdultChannel(channel) &&
    channel.streamUrl.trim().isNotEmpty;

/// Coordonne une série de tests cast contre UN récepteur. Notifie
/// ses listeners à chaque transition pour que l'UI suive en direct.
class DiagnosticBatchRunner extends ChangeNotifier {
  DiagnosticBatchRunner({
    required this.device,
    required this.channels,
    CastManager? manager,
    Duration interTestPause = _kInterTestPause,
  })  : _manager = manager ?? CastManager.instance,
        _interTestPause = interTestPause;

  final CastDevice device;
  final List<Channel> channels;
  final CastManager _manager;
  final Duration _interTestPause;
  int? _ownedRevision;
  bool _disposed = false;

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
    if (_running || _disposed || TvActivity.isBusy) return;
    final int scope = ActiveProfile.instance.scopeListenable.value;
    void scopeChanged() {
      if (scope != ActiveProfile.instance.scopeListenable.value) cancel();
    }

    ActiveProfile.instance.scopeListenable.addListener(scopeChanged);
    _running = true;
    _cancelled = false;
    _results.clear();
    _currentIndex = 0;
    _notify();
    int expectedRevision = _manager.sessionRevision;

    try {
      for (int i = 0; i < channels.length; i++) {
        if (_cancelled ||
            _disposed ||
            TvActivity.isBusy ||
            expectedRevision != _manager.sessionRevision ||
            scope != ActiveProfile.instance.scopeListenable.value) break;
        _currentIndex = i;
        _notify();
        if (_cancelled ||
            _disposed ||
            TvActivity.isBusy ||
            expectedRevision != _manager.sessionRevision ||
            scope != ActiveProfile.instance.scopeListenable.value) break;

        final Channel ch = channels[i];
        if (!_diagnosticChannelAllowed(ch)) continue;
        final DateTime startedAt = DateTime.now();
        bool timedOutHere = false;

        // 1) Cast — on encaisse l'exception, le diagnostic est déjà
        //    archivé par le CastManager dans tous les cas (finally).
        try {
          final int before = _manager.sessionRevision;
          final Future<void> attempt = _manager.castTo(
            device,
            streamUrl: ch.streamUrl,
            title: ch.name,
            channelName: ch.name,
            channelGenre: ch.genre.label,
          );
          _ownedRevision = _manager.sessionRevision;
          // Refus avant démarrage : ce numéro appartient à la session
          // précédente, jamais au diagnostic qui vient d'être refusé.
          if (_ownedRevision == before) {
            _ownedRevision = null;
            _cancelled = true;
            break;
          }
          await attempt;
        } on TimeoutException {
          // Le timeout du manager nettoie lui-même et incrémente sa
          // révision. Cette fermeture n'est pas une nouvelle sélection.
          timedOutHere = _ownedRevision != null &&
              _manager.sessionRevision == _ownedRevision! + 1 &&
              _manager.state == CastState.error;
        } on Exception {
          // Pas d'action — l'erreur est enregistrée dans le diag.
        }

        // 2) Ramasser le diagnostic qui vient d'être archivé.
        final List<CastSessionDiagnostic> recent = _manager.recentDiagnostics;
        for (final CastSessionDiagnostic diagnostic in recent) {
          if (!diagnostic.startedAt.isBefore(startedAt) &&
              diagnostic.device.id == device.id &&
              diagnostic.originalUrl == ch.streamUrl) {
            _results.add(diagnostic);
            _notify();
            break;
          }
        }

        if (_cancelled ||
            _disposed ||
            (!timedOutHere && _ownedRevision != _manager.sessionRevision)) {
          _cancelled = true;
          break;
        }

        // 3) Disconnect + pause entre tests.
        try {
          if (timedOutHere) {
            expectedRevision = _manager.sessionRevision;
            _ownedRevision = null;
          } else {
            final Future<void> stopping = _manager.disconnect();
            expectedRevision = _manager.sessionRevision;
            _ownedRevision = null;
            await stopping;
          }
        } on Exception catch (e) {
          if (kDebugMode) debugPrint('[Diag] disconnect: $e');
        }

        if (i + 1 < channels.length && !_cancelled) {
          await Future<void>.delayed(_interTestPause);
        }
      }
    } finally {
      ActiveProfile.instance.scopeListenable.removeListener(scopeChanged);
      _ownedRevision = null;
      _running = false;
      _notify();
    }
  }

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    // Annuler coupe seulement la tentative possédée par CE diagnostic.
    // Une sélection plus récente sur un autre écran reste intacte.
    if (_ownedRevision == _manager.sessionRevision) {
      unawaited(_manager.disconnect());
    }
    _ownedRevision = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }

  // -------- Agrégats pour l'UI résumé --------

  int get successCount =>
      _results.where((CastSessionDiagnostic d) => d.success).length;
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
        'app': 'ZUNO',
        'device': <String, dynamic>{
          'name': device.name,
          'kind': device.kind.name,
          'host': device.host,
          if (device.manufacturer != null) 'manufacturer': device.manufacturer,
          if (device.model != null) 'model': device.model,
        },
        'sampleSize': _results.length,
        'plannedSize': channels.length,
        'cancelled': _cancelled,
        'successCount': successCount,
        'failureCount': failureCount,
        'successRate': _results.isEmpty ? 0.0 : successCount / _results.length,
        'averageSuccessLatencyMs': averageSuccessLatencyMs,
        'winningStrategies': winningStrategyCounts,
      },
      'sessions': _results
          .map((CastSessionDiagnostic d) => d.toJson())
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }
}
