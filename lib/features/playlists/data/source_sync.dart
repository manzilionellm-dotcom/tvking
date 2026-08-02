// =========================================================
//  source_sync.dart — « Synchroniser » : le MIROIR de la source
// =========================================================
//  Demande du client (2026-08-02), mot pour mot :
//    « un bouton de mise à jour qui est tellement puissant.
//      – si j'appuie, si j'ai enlevé toutes les chaînes, je reste
//        avec zéro chaînes ;
//      – si j'ajoutais des films, le film vient direct ;
//      – si j'ajoutais une autre chaîne, la chaîne s'ajoute direct. »
//
//  Autrement dit : après l'appui, l'app doit refléter EXACTEMENT ce que
//  le revendeur a dans son panel — les ajouts ET les retraits. C'est ce
//  dernier point qui manquait : jusqu'ici l'app savait ajouter, jamais
//  enlever, et un abonnement vidé restait plein sur le téléphone.
//
//  Quatre étages, dans cet ordre — chacun sert à quelque chose :
//    1. SOURCE   — le revendeur a peut-être ASSIGNÉ une autre source à
//                  cette MAC. On la récupère avant tout le reste, sinon
//                  on synchroniserait l'ancienne.
//    2. CHAÎNES  — chaque source est re-téléchargée et REMPLACE la
//                  précédente (miroir, y compris à zéro).
//    3. CINÉMA   — films et séries vivent dans un cache (mémoire +
//                  disque) : sans purge, un film ajouté ce matin
//                  n'apparaîtrait qu'au prochain vidage de cache. On
//                  force la relecture.
//    4. RAPPORT  — ce qui a bougé, en clair : « +12 chaînes, −340 ».
//
//  CE QU'ON NE FAIT PAS : `pruneEmptyPlaylists()`. Une source tombée à
//  zéro doit RESTER enregistrée. Le client veut voir zéro chaîne, pas
//  perdre son abonnement — quand le revendeur remet des chaînes, le
//  prochain appui doit les ramener sans qu'il ait rien à ressaisir.
// =========================================================
import 'dart:async';

import '../../../core/crash/crash_reporting.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/series_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../domain/playlist.dart';
import 'playlist_repository.dart';
import 'remote_source_repository.dart';

/// Étape en cours — sert à écrire un mot juste sous la roue qui tourne,
/// au lieu d'un « Chargement… » qui ne dit rien.
enum SyncPhase {
  /// On demande au serveur si le revendeur a changé la source.
  source,

  /// On re-télécharge les chaînes de chaque source.
  channels,

  /// On repasse chercher les films et les séries.
  cinema,

  /// Fini.
  done,
}

/// Ce qui a réellement bougé. Tout est calculé par COMPARAISON entre
/// l'avant et l'après — jamais deviné.
class SyncReport {
  const SyncReport({
    required this.channelsBefore,
    required this.channelsAfter,
    required this.added,
    required this.removed,
    required this.movies,
    required this.series,
    required this.sourcesOk,
    required this.sourcesFailed,
    this.newSourceReceived = false,
  });

  final int channelsBefore;
  final int channelsAfter;

  /// Chaînes présentes après et absentes avant.
  final int added;

  /// Chaînes présentes avant et absentes après — le retrait, enfin.
  final int removed;

  final int movies;
  final int series;

  /// Sources re-téléchargées avec succès / en échec (fournisseur
  /// injoignable, identifiants refusés…).
  final int sourcesOk;
  final int sourcesFailed;

  /// Le revendeur avait assigné une NOUVELLE source à cet appareil.
  final bool newSourceReceived;

  /// Rien n'a changé : ni chaîne ajoutée, ni chaîne retirée.
  bool get unchanged => added == 0 && removed == 0 && !newSourceReceived;

  /// Toutes les sources ont échoué alors qu'il y en avait : on n'a rien
  /// pu vérifier, il ne faut donc PAS annoncer « à jour ».
  bool get allFailed => sourcesOk == 0 && sourcesFailed > 0;
}

/// Le compte rendu de fin, en une phrase. Volontairement ICI et non dans
/// le bouton : c'est la seule preuve, pour le client, que l'appui a servi
/// à quelque chose — ça mérite d'être testé, pas enfoui dans un widget.
///
/// L'ordre des cas n'est pas cosmétique :
///   1. tout a échoué → on le dit, et on rassure : rien n'a bougé ;
///   2. quelque chose a changé → on annonce QUOI, ajouts et retraits ;
///   3. rien n'a changé → « déjà à jour », avec le compte pour preuve.
String syncResultText(SyncReport r) {
  if (r.allFailed) {
    return 'Source injoignable. Rien n\'a été modifié — '
        'tes chaînes sont intactes.';
  }
  final List<String> bits = <String>[];
  if (r.added > 0) bits.add('${r.added} ajoutée${r.added > 1 ? 's' : ''}');
  if (r.removed > 0) {
    bits.add('${r.removed} retirée${r.removed > 1 ? 's' : ''}');
  }
  if (bits.isEmpty) {
    // Zéro chaîne n'est PAS une erreur : c'est le miroir fidèle d'une
    // source que le revendeur a vidée. On l'annonce comme un fait.
    if (r.channelsAfter == 0) {
      return 'Aucune chaîne dans ta source. C\'est bien à jour.';
    }
    return 'Déjà à jour — ${r.channelsAfter} chaînes.';
  }
  final String head = r.newSourceReceived ? 'Nouvelle source reçue · ' : '';
  return '$head${bits.join(' · ')} → ${r.channelsAfter} chaînes'
      '${r.movies > 0 ? ', ${r.movies} films' : ''}.';
}

abstract final class SourceSync {
  /// Une seule synchro à la fois : deux passes simultanées se battraient
  /// sur les mêmes lignes SQLite et doubleraient le pic mémoire.
  static bool _running = false;
  static bool get isRunning => _running;

  /// Lance le miroir complet. Ne lance JAMAIS d'exception : chaque étage
  /// est protégé, et ce qui a échoué ressort dans le rapport.
  static Future<SyncReport> run({
    void Function(SyncPhase phase)? onPhase,
  }) async {
    if (_running) {
      // Un appui pendant qu'une synchro tourne : on ne double pas, on
      // rend l'état actuel sans rien casser.
      final int n = PlaylistRepository.instance.currentChannels.length;
      return SyncReport(
        channelsBefore: n,
        channelsAfter: n,
        added: 0,
        removed: 0,
        movies: VodRepository.instance.cachedMovies.length,
        series: 0,
        sourcesOk: 0,
        sourcesFailed: 0,
      );
    }
    _running = true;
    try {
      // ---- Photo AVANT : les identifiants, pas le compte -------------
      // Un simple compteur ne dirait pas si 10 chaînes ont été
      // remplacées par 10 autres. On compare les identités.
      final Set<String> before = <String>{
        for (final Channel c in PlaylistRepository.instance.currentChannels)
          c.id,
      };
      final int sourcesBefore =
          PlaylistRepository.instance.currentPlaylists.length;

      // ---- 1. Le revendeur a-t-il changé la source ? -----------------
      onPhase?.call(SyncPhase.source);
      try {
        await RemoteSourceRepository.sync();
      } catch (e, s) {
        CrashReporting.instance.recordError(e, s, context: 'SourceSync.remote');
      }
      // On ne se fie PAS au résultat renvoyé : `loaded` vaut aussi quand
      // la source était déjà là, et on annoncerait « nouvelle source » à
      // chaque appui. Ce qui fait foi, c'est qu'une source de PLUS soit
      // apparue dans la base.
      final bool newSource =
          PlaylistRepository.instance.currentPlaylists.length > sourcesBefore;

      // ---- 2. Les chaînes, en miroir --------------------------------
      onPhase?.call(SyncPhase.channels);
      int ok = 0;
      int failed = 0;
      List<Playlist> sources = const <Playlist>[];
      try {
        sources = await PlaylistRepository.instance.getAllPlaylists();
      } catch (e, s) {
        CrashReporting.instance.recordError(e, s, context: 'SourceSync.list');
      }
      for (final Playlist p in sources) {
        try {
          // allowEmpty : c'est ICI que « zéro reste zéro » se joue.
          if (await PlaylistRepository.instance
              .refreshPlaylist(p, allowEmpty: true)) {
            ok++;
          } else {
            failed++;
          }
        } catch (_) {
          // Une source injoignable ne doit pas empêcher les autres de se
          // mettre à jour — on compte et on continue.
          failed++;
        }
      }

      // ---- 3. Cinéma : purge du cache, sinon rien ne « vient direct »
      onPhase?.call(SyncPhase.cinema);
      int movies = 0;
      int series = 0;
      try {
        movies = (await VodRepository.instance.fetchMovies(forceRefresh: true))
            .length;
      } catch (e, s) {
        CrashReporting.instance.recordError(e, s, context: 'SourceSync.vod');
      }
      try {
        series =
            (await SeriesRepository.instance.fetchSeries(forceRefresh: true))
                .length;
      } catch (e, s) {
        CrashReporting.instance.recordError(e, s, context: 'SourceSync.series');
      }

      // ---- 4. Photo APRÈS et différence -----------------------------
      final Set<String> after = <String>{
        for (final Channel c in PlaylistRepository.instance.currentChannels)
          c.id,
      };
      onPhase?.call(SyncPhase.done);
      return SyncReport(
        channelsBefore: before.length,
        channelsAfter: after.length,
        added: after.difference(before).length,
        removed: before.difference(after).length,
        movies: movies,
        series: series,
        sourcesOk: ok,
        sourcesFailed: failed,
        newSourceReceived: newSource,
      );
    } finally {
      _running = false;
    }
  }
}
