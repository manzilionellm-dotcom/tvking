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
//    3. (redémarrage seulement) attend une nouvelle publication Films /
//       Séries. Le catalogue DÉJÀ sur la box reste utilisable en cas de panne.
//
//  [status] permet à l'interface d'afficher « Mise à jour… » pendant la
//  passe, puis de l'effacer. Une seule passe à la fois (garde interne +
//  verrou de PlaylistRepository.refreshAll).
// =========================================================
import 'package:flutter/foundation.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import 'tv_activity.dart';

abstract final class TvContentRefresh {
  /// Vrai pendant qu'une passe de mise à jour tourne (affichage discret).
  static final ValueNotifier<bool> running = ValueNotifier<bool>(false);
  static Future<void>? _work;
  static bool _workAutomatic = false;
  static bool _workIncludesCinema = false;

  /// Phrase à montrer si une liste n'a pas pu être actualisée.
  /// `null` quand tout va bien.
  static final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// Passe automatique (2 min après l'ouverture, puis toutes les 6 h) :
  /// une liste synchronisée il y a moins de 6 h n'est pas retéléchargée.
  /// Mesuré le 05/10/2026 sur la box de test : avec 2 minutes, chaque
  /// ouverture retéléchargeait les 3 listes du client, « Mise à jour… »
  /// restait affiché 10 minutes, et le revendeur croyait que sa liste
  /// n'arrivait pas. Les 6 h sont déjà le rythme de la passe périodique.
  static const Duration autoSkipWindow = Duration(hours: 6);

  /// Bouton Redémarrer : le client demande explicitement du neuf, on ne
  /// saute que ce qui vient d'être installé à l'instant (par l'étape 1).
  static const Duration manualSkipWindow = Duration(minutes: 2);

  /// Fenêtre « déjà à jour » d'une passe. Pur, testé sans écran.
  /// [automatic] : passe lancée par l'app (pas par le bouton).
  /// [fullLegacy] : repli `zuno.refresh.auto_full` (ancien comportement).
  static Duration skipWindow({
    required bool automatic,
    required bool fullLegacy,
  }) {
    if (automatic && !fullLegacy) return autoSkipWindow;
    return manualSkipWindow;
  }

  /// Lance une passe complète.
  ///
  /// [waitIdle] : attendre que le client ait quitté Direct / le lecteur
  /// (TvActivity) — re-parser 30 000 chaînes pendant qu'il zappe figeait la
  /// box. Le bouton Redémarrer ne l'utilise pas : il ramène déjà à l'accueil.
  /// [clearCinema] : forcer puis attendre Films / Séries (demande manuelle),
  /// sans effacer le dernier catalogue exploitable en cas de panne.
  /// [automatic] : passe lancée par l'app (2 min / 6 h) et non par le
  /// bouton ; par défaut égal à [waitIdle], qui ne vaut vrai que pour elle.
  static Future<void> run({
    bool waitIdle = false,
    bool clearCinema = false,
    bool? automatic,
  }) async {
    if (BootGuard.instance.safeMode) return;
    final bool auto = automatic ?? waitIdle;
    final Duration skip = skipWindow(
      automatic: auto,
      fullLegacy: RepairFlags.autoRefreshFull,
    );
    if (waitIdle) {
      for (int i = 0; i < 30 && TvActivity.isBusy; i++) {
        await Future<void>.delayed(const Duration(seconds: 60));
      }
      if (TvActivity.isBusy) return; // toujours occupé → prochain passage
    }
    final Future<void>? current = _work;
    if (current != null) {
      final bool mustForce = !auto &&
          (_workAutomatic || (clearCinema && !_workIncludesCinema));
      await current;
      if (mustForce) {
        await run(clearCinema: clearCinema, automatic: false);
      }
      return;
    }
    _workAutomatic = auto;
    _workIncludesCinema = clearCinema;
    late final Future<void> work;
    work = _runOnce(
      automatic: auto,
      clearCinema: clearCinema,
      skip: skip,
    ).whenComplete(() {
      if (identical(_work, work)) _work = null;
    });
    _work = work;
    await work;
  }

  static Future<void> _runOnce({
    required bool automatic,
    required bool clearCinema,
    required Duration skip,
  }) async {
    final bool auto = automatic;
    // La pastille « Mise à jour… » affiche le détail du bus de progression :
    // on efface celui d'un import précédent avant de commencer.
    ImportProgressBus.clear();
    running.value = true;
    notice.value = null;
    final Stopwatch sw = Stopwatch()..start();
    try {
      // 1) Nouvelle source posée dans le panel ? Le bouton Redémarrer
      //    retente aussi les listes mises de côté après un refus.
      final RemoteSyncResult sync =
          await RemoteSourceRepository.sync(force: !auto);
      // 2) Une demande manuelle relit vraiment les chaînes, même récentes.
      //    Seule la passe automatique utilise sa fenêtre d’économie réseau.
      final int ok = await PlaylistRepository.instance
          .refreshAll(skipSyncedWithin: auto ? skip : null);
      notice.value = PlaylistRepository.instance.refreshWarning.value;
      if (sync == RemoteSyncResult.networkError ||
          sync == RemoteSyncResult.sourceFailed) {
        notice.value = 'Actualisation incomplète : une source n’a pas répondu.';
      }
      // Le bouton attend une publication réelle des films et séries,
      // même si le cache est récent. Le dernier catalogue reste disponible
      // si le fournisseur échoue ; aucune fausse fin « à jour ».
      if (clearCinema) {
        final CinemaRepository cinema = CinemaRepository.instance;
        if ((await cinema.sources()).isNotEmpty) {
          final bool movies = await cinema.refreshNow(CinemaKind.movie);
          final bool series = await cinema.refreshNow(CinemaKind.series);
          if (!movies || !series) {
            notice.value = 'Actualisation incomplète du cinéma. Réessaie plus tard.';
          }
        }
      }
      BlackBox.instance.info(
        'SYNC',
        'mise à jour ${auto ? 'automatique' : 'demandée'} : $ok source(s) '
        'actualisée(s) en ${sw.elapsedMilliseconds} ms '
        '(sources récentes ignorées : ${auto ? skip.inMinutes : 0} min)',
      );
    } catch (e) {
      // Garder le dernier contenu utilisable, mais afficher l’échec réel.
      notice.value = 'Actualisation incomplète. Réessaie plus tard.';
      BlackBox.instance.warn('SYNC', 'mise à jour interrompue : $e');
    } finally {
      running.value = false;
    }
  }
}
