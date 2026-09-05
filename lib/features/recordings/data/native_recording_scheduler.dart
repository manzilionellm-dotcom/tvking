// =========================================================
//  native_recording_scheduler.dart — Pont vers le natif Android
// =========================================================
//  Parle au plugin tvking_device (canal `…/recording_scheduler`) :
//  poser/retirer les alarmes exactes, lire l'état d'une capture faite
//  par le service natif, connaître l'espace libre. Sur les autres
//  plateformes (Windows, Tizen, web), [isSupported] est false et le
//  planificateur Dart capte lui-même (tant que l'app tourne).
//
//  Best-effort : jamais d'exception vers l'appelant — une méthode
//  manquante (vieux build sans le plugin) se comporte comme « non
//  supporté ».
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// État d'une capture vu du natif.
class NativeRecordingStatus {
  const NativeRecordingStatus({
    required this.id,
    required this.state,
    required this.bytes,
    this.file,
    this.startedAt,
    this.endedAt,
    this.error,
  });

  final String id;

  /// `planned` | `recording` | `done` | `failed`.
  final String state;
  final int bytes;
  final String? file;
  final int? startedAt;
  final int? endedAt;
  final String? error;

  bool get isRecording => state == 'recording';
  bool get isDone => state == 'done';
  bool get isFailed => state == 'failed';

  static NativeRecordingStatus? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    if (id is! String) return null;
    return NativeRecordingStatus(
      id: id,
      state: raw['state']?.toString() ?? 'planned',
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
      file: raw['file']?.toString(),
      startedAt: (raw['startedAt'] as num?)?.toInt(),
      endedAt: (raw['endedAt'] as num?)?.toInt(),
      error: raw['error']?.toString(),
    );
  }
}

class NativeRecordingScheduler {
  NativeRecordingScheduler._();
  static final NativeRecordingScheduler instance = NativeRecordingScheduler._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/recording_scheduler');

  /// Le natif n'existe que sur Android (plugin tvking_device).
  bool get isSupported => !kIsWeb && Platform.isAndroid && !_missing;

  /// Passe à true au premier MissingPluginException : inutile de
  /// réessayer à chaque tick.
  bool _missing = false;

  /// Point d'injection pour les tests (remplace l'appel natif).
  @visibleForTesting
  Future<Object?> Function(String method, Map<String, Object?> args)? invoker;

  Future<Object?> _call(String method,
      [Map<String, Object?> args = const <String, Object?>{}]) async {
    if (invoker != null) return invoker!(method, args);
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      _missing = true;
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[NativeSched] $method: ${e.message}');
      return null;
    }
  }

  Future<bool> schedule({
    required String id,
    required String url,
    required String file,
    required String title,
    required int startMs,
    required int stopMs,
    required String notifTitle,
    required String channelName,
    required String channelDesc,
  }) async {
    final Object? r = await _call('schedule', <String, Object?>{
      'id': id,
      'url': url,
      'file': file,
      'title': title,
      'startMs': startMs,
      'stopMs': stopMs,
      'notifTitle': notifTitle,
      'channelName': channelName,
      'channelDesc': channelDesc,
    });
    return r == true;
  }

  Future<void> cancel(String id) async {
    await _call('cancel', <String, Object?>{'id': id});
  }

  /// Le Dart a intégré le résultat : le natif peut oublier l'entrée.
  Future<void> forget(String id) async {
    await _call('forget', <String, Object?>{'id': id});
  }

  Future<NativeRecordingStatus?> status(String id) async {
    return NativeRecordingStatus.fromMap(
        await _call('status', <String, Object?>{'id': id}));
  }

  Future<List<NativeRecordingStatus>> statusAll() async {
    final Object? r = await _call('statusAll');
    if (r is! List) return const <NativeRecordingStatus>[];
    return r
        .map(NativeRecordingStatus.fromMap)
        .whereType<NativeRecordingStatus>()
        .toList(growable: false);
  }

  Future<bool> canScheduleExact() async {
    final Object? r = await _call('canScheduleExact');
    return r == true;
  }

  Future<bool> openExactAlarmSettings() async {
    final Object? r = await _call('openExactAlarmSettings');
    return r == true;
  }

  /// Octets libres sur le volume de [path] (StatFs). null = inconnu.
  Future<int?> freeSpace(String path) async {
    final Object? r = await _call('freeSpace', <String, Object?>{'path': path});
    return r is num ? r.toInt() : null;
  }
}
