// =========================================================
//  box_reset.dart — Remise à neuf de la box demandée depuis le panel
// =========================================================
//  Demande du propriétaire (06/10/2026) : « un bouton que j'appuie, et
//  l'application doit être comme neuve ; moi j'ajoute ensuite à distance ».
//
//  Chaîne : panel « Réinitialiser la box » → Worker retire toutes les
//  listes de la MAC (panel et client) et écrit `devices.reset_at` → la box
//  reçoit l'ordre « reset » (WebSocket) ou lit `reset_at` dans le statut à
//  son prochain tour (box éteinte comprise). Ici on décide et on efface :
//  listes (chaînes, favoris et récents de chaque liste), historique, guide,
//  recherches, mémoire des listes servies et des refus. La licence, la
//  boîte noire, l'identité de la box et les interrupteurs restent.
//
//  Idempotent : l'heure appliquée est mémorisée ; un même `reset_at` n'est
//  jamais rejoué. Une installation neuve part de 0 : un ancien `reset_at`
//  s'applique une fois sur une box vide, sans effet.
// =========================================================
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../channels/data/recent_searches_repository.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../epg/data/epg_repository.dart';
import '../domain/playlist.dart';
import 'import_progress.dart';
import 'playlist_repository.dart';
import 'remote_source_repository.dart';

abstract final class BoxReset {
  /// Heure (ms) de la dernière remise à neuf appliquée sur cette box.
  static const String appliedKey = 'zuno.reset.applied_at.v1';

  /// Règle pure (testée) : on applique seulement une demande plus récente
  /// que la dernière appliquée. `0` = aucune demande.
  static bool shouldApply({required int resetAt, required int appliedAt}) {
    return resetAt > 0 && resetAt > appliedAt;
  }

  /// Lit la demande portée par le statut et l'applique si elle est neuve.
  /// Renvoie vrai si la box a été remise à neuf maintenant.
  static Future<bool> maybeApply(int resetAt) async {
    if (RepairFlags.remoteResetOff) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int applied = prefs.getInt(appliedKey) ?? 0;
    if (!shouldApply(resetAt: resetAt, appliedAt: applied)) return false;
    // Mémorisée AVANT d'effacer : une mort du processus au milieu ne
    // rejoue pas l'effacement en boucle ; le tour suivant relit les listes.
    await prefs.setInt(appliedKey, resetAt);
    final int lists = await wipe(reason: 'réinitialisation par le panel');
    BlackBox.instance.info(
      'PANEL',
      'box remise à neuf sur ordre du panel : $lists liste(s), favoris, '
      'historique, guide et recherches effacés ; relecture des listes',
    );
    return true;
  }

  /// Efface tout ce qui vient des listes. Renvoie le nombre de listes
  /// effacées. Chaque suppression passe par `deletePlaylist` : elle est
  /// journalisée avec [reason] et emporte favoris et récents de la liste.
  static Future<int> wipe({required String reason}) async {
    BlackBox.instance.breadcrumb('Remise à neuf de la box');
    ImportProgressBus.clear();
    final List<Playlist> all = await PlaylistRepository.instance.getAllPlaylists();
    int n = 0;
    for (final Playlist p in all) {
      final int? id = p.id;
      if (id == null) continue;
      try {
        await PlaylistRepository.instance.deletePlaylist(id, reason: reason);
        n++;
      } catch (e) {
        BlackBox.instance.warn('DB', 'liste $id non effacée à la remise à neuf : $e');
      }
    }
    await _quiet(() => RecentlyWatchedRepository.instance.clear(), 'récents');
    await _quiet(() => WatchHistoryRepository.instance.clear(), 'historique');
    await _quiet(() => RecentSearchesRepository.instance.clearAll(), 'recherches');
    await _quiet(() => EpgRepository.instance.clearAll(), 'guide');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(RemoteSourceRepository.rememberedKey);
    await prefs.remove(RemoteSourceRepository.failuresKey);
    BlackBox.instance.breadcrumb('');
    return n;
  }

  static Future<void> _quiet(Future<void> Function() job, String what) async {
    try {
      await job();
    } catch (e) {
      BlackBox.instance.warn('DB', '$what non effacé à la remise à neuf : $e');
    }
  }
}
