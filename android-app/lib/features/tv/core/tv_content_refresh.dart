// =========================================================
//  tv_content_refresh.dart — « Va chercher tout ce qui est nouveau »
// =========================================================
//  UNE seule routine, utilisée par :
//    • le bouton REDÉMARRER (le client, ou le revendeur au téléphone,
//      demande « redémarre pour que la chaîne entre ») ;
//    • la vérification AUTOMATIQUE 2 minutes après l'ouverture de l'app,
//      puis toutes les 6 heures tant que la box reste allumée.
//
//  Ce qu'elle fait, dans l'ordre :
//    1. demande au panel s'il y a une NOUVELLE source pour cette MAC
//       (Xtream / M3U posée par le revendeur) et l'installe ;
//    2. RE-TÉLÉCHARGE la liste de chaînes de CHAQUE source active : c'est
//       l'étape qui manquait. Avant, « Redémarrer » ne relisait que le cache
//       local → une chaîne ajoutée chez le fournisseur n'entrait jamais
//       avant 24 h ;
//    3. (redémarrage seulement) vide le cache Films / Séries pour que les
//       nouveaux titres apparaissent à la prochaine ouverture.
//
//  [status] permet à l'interface d'afficher « Mise à jour… » pendant la
//  passe, puis de l'effacer. Une seule passe à la fois (garde interne +
//  verrou de PlaylistRepository.refreshAll).
// =========================================================
import 'package:flutter/foundation.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/blackbox/black_box.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import 'tv_activity.dart';

abstract final class TvContentRefresh {
  /// Vrai pendant qu'une passe de mise à jour tourne (affichage discret).
  static final ValueNotifier<bool> running = ValueNotifier<bool>(false);

  /// Lance une passe complète.
  ///
  /// [waitIdle] : attendre que le client ait quitté Direct / le lecteur
  /// (TvActivity) — re-parser 30 000 chaînes pendant qu'il zappe figeait la
  /// box. Le bouton Redémarrer ne l'utilise pas : il ramène déjà à l'accueil.
  /// [clearCinema] : vider le cache Films / Séries (redémarrage uniquement,
  /// pour ne jamais vider un écran que le client est en train de parcourir).
  static Future<void> run({
    bool waitIdle = false,
    bool clearCinema = false,
  }) async {
    if (BootGuard.instance.safeMode) return;
    if (running.value) return; // une passe à la fois
    if (waitIdle) {
      for (int i = 0; i < 30 && TvActivity.isBusy; i++) {
        await Future<void>.delayed(const Duration(seconds: 60));
      }
      if (TvActivity.isBusy) return; // toujours occupé → prochain passage
    }
    running.value = true;
    final Stopwatch sw = Stopwatch()..start();
    try {
      // 1) Nouvelle source posée dans le panel ?
      await RemoteSourceRepository.sync();
      // 2) Nouvelles chaînes chez le fournisseur ? Une source installée à
      //    l'instant par l'étape 1 n'est pas re-téléchargée une 2e fois.
      final int ok = await PlaylistRepository.instance
          .refreshAll(skipSyncedWithin: const Duration(minutes: 2));
      // 3) Nouveaux films / séries (cache mémoire vidé → relu à l'ouverture).
      if (clearCinema) CinemaRepository.instance.clear();
      BlackBox.instance.info('SYNC',
          'mise à jour : $ok source(s) actualisée(s) en ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      // Silencieux pour le client : la mise à jour est un confort, jamais
      // une cause de panne. La trace reste dans la boîte noire.
      BlackBox.instance.warn('SYNC', 'mise à jour interrompue : $e');
    } finally {
      running.value = false;
    }
  }
}
