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
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
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

  // ---------------------------------------------------------------
  //  « TÉLÉCHARGER LA SAISON » (façon Netflix, 27/09/2026)
  //  Un seul appui met tous les épisodes non téléchargés en FILE D'ATTENTE.
  //  Ils partent UN PAR UN, jamais en parallèle : la plupart des abonnements
  //  IPTV n'autorisent qu'1 ou 2 connexions simultanées — 10 téléchargements
  //  en même temps feraient refuser le compte (et couperaient le direct).
  //  Épisode terminé ou en échec → le suivant démarre ; le client met en
  //  pause → la file s'arrête (c'est sa décision) ; plus de place → arrêt.
  //  La file vit tant que l'app est ouverte : après un redémarrage, les
  //  épisodes déjà commencés se reprennent, les autres se relancent d'un
  //  appui sur le même bouton (les épisodes finis sont ignorés).
  // ---------------------------------------------------------------

  static final List<VodMovie> _queue = <VodMovie>[];
  static String? _current;
  static StreamSubscription<List<Download>>? _queueSub;

  /// Nombre d'épisodes encore en attente (l'épisode en cours non compris).
  static final ValueNotifier<int> queued = ValueNotifier<int>(0);

  /// Vrai si [id] est en file d'attente ou en cours dans la file.
  static bool isQueued(String id) =>
      _current == id || _queue.any((VodMovie m) => m.id == id);

  /// Met en file tous les épisodes de [episodes] pas encore téléchargés.
  /// Renvoie le nombre d'épisodes ajoutés (0 = tout est déjà là / en file).
  static Future<int> startSeason(List<VodMovie> episodes) async {
    await DownloadsRepository.instance.initialize();
    int added = 0;
    for (final VodMovie m in episodes) {
      final Download? d = DownloadsRepository.instance.byId(m.id);
      if (d != null && (d.isDone || d.status == DownloadStatus.downloading)) {
        continue;
      }
      if (isQueued(m.id)) continue;
      _queue.add(m);
      added++;
    }
    queued.value = _queue.length;
    _queueSub ??= DownloadsRepository.instance.stream.listen(_onDownloads);
    BlackBox.instance.info('CINEMA', 'saison : $added épisode(s) en file');
    if (_current == null) await _next();
    return added;
  }

  static Future<void> _next() async {
    while (_queue.isNotEmpty) {
      final VodMovie m = _queue.removeAt(0);
      queued.value = _queue.length;
      final CinemaDownloadStart r = await start(m);
      if (r == CinemaDownloadStart.noSpace) {
        _queue.clear();
        queued.value = 0;
        _current = null;
        return;
      }
      if (r == CinemaDownloadStart.alreadyThere) continue;
      _current = m.id;
      return;
    }
    _current = null;
  }

  static void _onDownloads(List<Download> all) {
    final String? id = _current;
    if (id == null) return;
    Download? d;
    for (final Download x in all) {
      if (x.id == id) {
        d = x;
        break;
      }
    }
    if (d == null ||
        d.status == DownloadStatus.done ||
        d.status == DownloadStatus.error) {
      _current = null;
      unawaited(_next()); // terminé, échoué ou supprimé → épisode suivant
    } else if (d.status == DownloadStatus.paused) {
      // Pause posée par le DIRECT (voir pauseForLive) : la file attend, elle
      // reprendra toute seule à la sortie du lecteur.
      if (_pausedForLive.contains(id)) return;
      // Pause décidée par le client : on arrête la file.
      _current = null;
      _queue.clear();
      queued.value = 0;
    }
  }

  // ---------------------------------------------------------------
  //  PRIORITÉ AU DIRECT (29/09/2026)
  //  Beaucoup d'abonnements n'autorisent qu'UNE connexion à la fois. Un
  //  film en cours de téléchargement occupe cette connexion → le serveur
  //  refuse la chaîne en direct (« le cinéma marche, pas les chaînes »).
  //  Le lecteur du direct met donc les téléchargements EN PAUSE à son
  //  ouverture et les RELANCE à sa fermeture (reprise HTTP Range : rien
  //  n'est perdu).
  // ---------------------------------------------------------------

  /// Téléchargements mis en pause par le direct (à relancer ensuite).
  static final Set<String> _pausedForLive = <String>{};

  /// Met en pause les téléchargements en cours (ouverture du direct).
  static Future<void> pauseForLive() async {
    try {
      final List<String> active = DownloadsRepository.instance.current
          .where((Download d) => d.status == DownloadStatus.downloading)
          .map((Download d) => d.id)
          .toList();
      if (active.isEmpty) return;
      _pausedForLive.addAll(active);
      for (final String id in active) {
        await DownloadsRepository.instance.pause(id);
      }
      BlackBox.instance.info('CINEMA', '${active.length} téléchargement(s) en pause pendant le direct');
    } catch (_) {
      // Jamais bloquant pour le direct.
    }
  }

  /// Relance les téléchargements mis en pause par le direct (sortie du lecteur).
  static Future<void> resumeAfterLive() async {
    if (_pausedForLive.isEmpty) return;
    final List<String> ids = _pausedForLive.toList();
    _pausedForLive.clear();
    for (final String id in ids) {
      try {
        await DownloadsRepository.instance.resume(id);
      } catch (_) {}
    }
    BlackBox.instance.info('CINEMA', '${ids.length} téléchargement(s) relancé(s) après le direct');
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
