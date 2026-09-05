// =========================================================
//  recording_storage_policy.dart — Gestion de l'espace des enregistrements
// =========================================================
//  Un magnétoscope qui remplit le disque jusqu'à faire planter la box
//  n'est pas un magnétoscope. Cette classe applique trois règles :
//
//    1. LIMITE D'ESPACE choisie par le client (5/10/20/50/100 Go, ou sans
//       limite) : au-delà, les enregistrements TERMINÉS les plus anciens
//       sont supprimés automatiquement (jamais un enregistrement en cours).
//    2. ESPACE LIBRE MINIMAL avant de démarrer une capture programmée
//       (500 Mo) : mieux vaut un « échec : espace insuffisant » lisible
//       qu'un fichier tronqué.
//    3. AFFICHAGE : « X utilisés · Y libres » dans « Mes enregistrements ».
//
//  La sélection des fichiers à purger est une fonction PURE (testée).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../vod/data/vod_download_service.dart';
import '../domain/recording.dart';
import 'native_recording_scheduler.dart';
import 'recording_repository.dart';

class RecordingStoragePolicy extends ChangeNotifier {
  RecordingStoragePolicy._();
  static final RecordingStoragePolicy instance = RecordingStoragePolicy._();

  static const String _prefLimitGb = 'rec_storage_limit_gb';

  /// Choix proposés (Go). 0 = sans limite.
  static const List<int> limitChoicesGb = <int>[0, 5, 10, 20, 50, 100];

  /// Espace libre minimal pour DÉMARRER une capture programmée.
  static const int minFreeBytesToStart = 500 * 1024 * 1024;

  int _limitGb = 0;
  bool _loaded = false;

  /// Limite en Go (0 = sans limite).
  int get limitGb => _limitGb;
  int get limitBytes => _limitGb * 1024 * 1024 * 1024;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _limitGb = p.getInt(_prefLimitGb) ?? 0;
    } catch (_) {
      _limitGb = 0;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLimitGb(int gb) async {
    _limitGb = gb < 0 ? 0 : gb;
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setInt(_prefLimitGb, _limitGb);
    } catch (_) {
      // best-effort : la limite reste appliquée pour la session.
    }
    unawaited(enforce());
  }

  /// Octets occupés par les enregistrements terminés (d'après la base).
  int usedBytes() {
    int total = 0;
    for (final Recording r in RecordingRepository.instance.current) {
      total += r.fileSizeBytes;
    }
    return total;
  }

  /// Espace libre du volume des enregistrements. Natif (StatFs) d'abord,
  /// `df` en repli (Windows/Linux), null si inconnu.
  Future<int?> freeBytes() async {
    try {
      final Directory dir =
          await RecordingRepository.instance.getRecordingsDir();
      final int? native =
          await NativeRecordingScheduler.instance.freeSpace(dir.path);
      if (native != null) return native;
      return await VodDownloadService.freeDiskBytes(dir.path);
    } catch (_) {
      return null;
    }
  }

  /// `true` s'il reste assez de place pour démarrer une capture.
  Future<bool> hasRoomToStart() async {
    final int? free = await freeBytes();
    if (free == null) return true; // inconnu → on ne bloque pas
    return free >= minFreeBytesToStart;
  }

  /// Sélection PURE des enregistrements à supprimer pour repasser sous
  /// [limitBytes] : les plus ANCIENS d'abord, jamais ceux en cours
  /// (`endedAt == null`). Renvoie une liste vide si rien à faire.
  @visibleForTesting
  static List<Recording> selectForPurge(
    List<Recording> all,
    int limitBytes,
  ) {
    if (limitBytes <= 0) return const <Recording>[];
    final List<Recording> finished = all
        .where((Recording r) => r.endedAt != null)
        .toList()
      ..sort((Recording a, Recording b) => a.startedAt.compareTo(b.startedAt));
    int total = 0;
    for (final Recording r in all) {
      total += r.fileSizeBytes;
    }
    final List<Recording> out = <Recording>[];
    for (final Recording r in finished) {
      if (total <= limitBytes) break;
      out.add(r);
      total -= r.fileSizeBytes;
    }
    return out;
  }

  /// Applique la limite : supprime les plus anciens terminés si besoin.
  /// Appelé à chaque fin d'enregistrement et à chaque changement de limite.
  Future<int> enforce() async {
    await load();
    final List<Recording> victims =
        selectForPurge(RecordingRepository.instance.current, limitBytes);
    for (final Recording r in victims) {
      try {
        await RecordingRepository.instance.delete(r);
      } catch (e) {
        if (kDebugMode) debugPrint('[RecStorage] purge KO ${r.filePath}: $e');
      }
    }
    if (victims.isNotEmpty) notifyListeners();
    return victims.length;
  }
}
