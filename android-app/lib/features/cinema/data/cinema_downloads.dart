// =========================================================
//  cinema_downloads.dart — Téléchargements du Cinéma (règles « box »)
// =========================================================
//  S'appuie sur le moteur existant (DownloadsRepository : reprise HTTP Range,
//  pause, persistance SQLite) et ajoute ce qu'il faut sur une box TV :
//
//  1. ESPACE : on refuse de démarrer s'il reste moins de [kMinFreeBytes]
//     (une box a souvent 8 Go au total ; un film HD pèse 1 à 4 Go). Mieux
//     vaut un refus clair qu'une box pleine qui ne démarre plus.
//  2. TÉLÉCHARGEMENT INTELLIGENT (même principe que « Download Next
//     Episode » de Netflix, documenté par Netflix) : quand un épisode
//     TÉLÉCHARGÉ est terminé, on l'efface et on télécharge le SUIVANT —
//     uniquement en Wi-Fi / câble, jamais en données mobiles, et seulement
//     si l'utilisateur avait lui-même téléchargé l'épisode fini (aucun
//     téléchargement surprise).
// =========================================================
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/blackbox/black_box.dart';
import '../../vod/data/download_repository.dart';
import '../../vod/domain/vod_movie.dart';

/// Espace libre minimal pour lancer un téléchargement (3 Go).
const int kMinFreeBytes = 3 * 1024 * 1024 * 1024;

/// Résultat d'une demande de téléchargement.
enum CinemaDownloadStart { started, alreadyThere, noSpace }

abstract final class CinemaDownloads {
  static const MethodChannel _device = MethodChannel('com.manzilionellm.tvking/device');

  /// Octets libres sur le volume des téléchargements (-1 = inconnu).
  static Future<int> freeBytes() async {
    try {
      final String path =
          (await getExternalStorageDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
      final int? v = await _device.invokeMethod<int>('getFreeBytes', <String, dynamic>{'path': path});
      return v ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Lance (ou reprend) le téléchargement de [m] si la place le permet.
  static Future<CinemaDownloadStart> start(VodMovie m) async {
    await DownloadsRepository.instance.initialize();
    final Download? d = DownloadsRepository.instance.byId(m.id);
    if (d != null && d.isDone) return CinemaDownloadStart.alreadyThere;
    final int free = await freeBytes();
    if (free >= 0 && free < kMinFreeBytes) {
      BlackBox.instance.warn('CINEMA', 'téléchargement refusé : ${free ~/ (1024 * 1024)} Mo libres');
      return CinemaDownloadStart.noSpace;
    }
    if (d != null) {
      await DownloadsRepository.instance.resume(m.id);
    } else {
      await DownloadsRepository.instance.start(m);
    }
    BlackBox.instance.info('CINEMA', 'téléchargement ${m.id}');
    return CinemaDownloadStart.started;
  }

  /// Épisode terminé → s'il était téléchargé : on l'efface et on télécharge
  /// le suivant (Wi-Fi / câble uniquement).
  static Future<void> onEpisodeFinished({required String finishedId, VodMovie? next}) async {
    await DownloadsRepository.instance.initialize();
    final Download? d = DownloadsRepository.instance.byId(finishedId);
    if (d == null || !d.isDone) return; // l'utilisateur ne l'avait pas téléchargé
    await DownloadsRepository.instance.delete(finishedId);
    BlackBox.instance.info('CINEMA', 'téléchargement intelligent : $finishedId vu → effacé');
    if (next == null) return;
    if (!await _unmeteredNetwork()) return;
    final CinemaDownloadStart r = await start(next);
    BlackBox.instance.info('CINEMA', 'téléchargement intelligent : suivant ${next.id} → ${r.name}');
  }

  static Future<bool> _unmeteredNetwork() async {
    try {
      final List<ConnectivityResult> r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }
}
