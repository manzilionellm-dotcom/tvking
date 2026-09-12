// =========================================================
//  short_epg_service.dart — Repli « EPG courte » Xtream (aperçu)
// =========================================================
//  Quand la base XMLTV locale ne connaît pas une chaîne (panel sans URL
//  XMLTV, sync pas encore passée, epg_channel_id absent), le panneau
//  Aperçu affichait « Programme non disponible » à vie. Ce service va
//  chercher les programmes « maintenant + suivants » de LA chaîne
//  affichée via l'API du panel (`get_short_epg`) :
//    • appel API léger — PAS une connexion de flux : ne consomme jamais
//      la connexion unique des comptes 1-conn ;
//    • UNE chaîne à la fois (celle de l'aperçu), derrière l'anti-rebond
//      de l'UI → jamais de rafale vers le panel ;
//    • cache mémoire 10 min + cache NÉGATIF (une chaîne sans EPG ne
//      re-déclenche pas une requête à chaque passage du focus) ;
//    • best-effort : toute erreur → liste vide, jamais d'exception.
// =========================================================

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/epg_program.dart';

class ShortEpgService {
  ShortEpgService._();
  static final ShortEpgService instance = ShortEpgService._();

  /// Cache par chaîne (positif ET négatif) — borné, TTL 10 min.
  final Map<String, ({DateTime at, List<EpgProgram> programs})> _cache =
      <String, ({DateTime at, List<EpgProgram> programs})>{};
  static const Duration _ttl = Duration(minutes: 10);
  static const int _cacheMax = 300;

  /// Demandes EN VOL, par chaîne.
  ///
  /// AJOUTÉ LE 12/09/2026, en branchant ce service sur la RECHERCHE. Il
  /// était écrit pour un seul appelant : l'aperçu de l'écran Chaînes, une
  /// chaîne à la fois, derrière un anti-rebond. La recherche, elle,
  /// affiche une rangée de vignettes qui se reconstruit à chaque lettre
  /// tapée — sans ce registre, la même chaîne partait plusieurs fois vers
  /// le panel avant que la première réponse n'ait eu le temps de remplir
  /// le cache. Un service prévu pour un appelant devient bruyant dès le
  /// second : on le rend sûr AVANT de le brancher, pas après.
  final Map<String, Future<List<EpgProgram>>> _enVol =
      <String, Future<List<EpgProgram>>>{};

  /// Les playlists, relues une fois par minute au plus.
  ///
  /// `_playlistOf` interrogeait la base à CHAQUE appel, pour toutes les
  /// playlists. Acceptable pour une chaîne ; absurde pour une rangée de
  /// vignettes qui défile.
  List<Playlist>? _playlists;
  DateTime? _playlistsAt;
  static const Duration _playlistsTtl = Duration(minutes: 1);

  /// Programmes à venir de [channel] via `get_short_epg`. `[]` si la chaîne
  /// n'est pas Xtream, si sa playlist n'a plus d'identifiants, ou si le
  /// panel ne répond rien d'exploitable.
  Future<List<EpgProgram>> upcomingFor(Channel channel) {
    final String? streamId = _xtreamStreamId(channel.id);
    if (streamId == null) return Future<List<EpgProgram>>.value(const <EpgProgram>[]);

    final ({DateTime at, List<EpgProgram> programs})? hit = _cache[channel.id];
    if (hit != null && DateTime.now().difference(hit.at) <= _ttl) {
      return Future<List<EpgProgram>>.value(hit.programs);
    }
    // Une demande déjà partie pour cette chaîne : on attend la même, on
    // n'en lance pas une deuxième.
    final Future<List<EpgProgram>>? dejaPartie = _enVol[channel.id];
    if (dejaPartie != null) return dejaPartie;

    final Future<List<EpgProgram>> f = _demander(channel, streamId);
    _enVol[channel.id] = f;
    return f;
  }

  Future<List<EpgProgram>> _demander(Channel channel, String streamId) async {
    List<EpgProgram> programs = const <EpgProgram>[];
    XtreamClient? client;
    try {
      final Playlist? p = await _playlistOf(channel.playlistId);
      if (p != null &&
          p.xtreamServer != null &&
          p.xtreamUsername != null &&
          p.xtreamPassword != null) {
        client = XtreamClient(
          serverUrl: p.xtreamServer!,
          username: p.xtreamUsername!,
          password: p.xtreamPassword!,
        );
        final List<EpgProgram> all =
            await client.fetchShortEpg(streamId: streamId);
        // On ne garde que l'en-cours + le futur (le passé n'aide personne
        // dans un panneau « à venir »).
        final DateTime now = DateTime.now();
        programs = all
            .where((EpgProgram x) => x.stopDateTime.isAfter(now))
            .toList(growable: false);
      }
    } catch (_) {
      programs = const <EpgProgram>[];
    } finally {
      client?.dispose();
    }

    if (_cache.length >= _cacheMax) {
      _cache.remove(_cache.keys.first); // éviction FIFO simple
    }
    _cache[channel.id] = (at: DateTime.now(), programs: programs);
    _enVol.remove(channel.id);
    return programs;
  }

  /// `xtream-1234` → `1234`, sinon null (chaîne non Xtream).
  static String? _xtreamStreamId(String channelId) {
    if (!channelId.startsWith('xtream-')) return null;
    final String id = channelId.substring('xtream-'.length);
    return id.isEmpty ? null : id;
  }

  Future<Playlist?> _playlistOf(int? playlistId) async {
    if (playlistId == null) return null;
    final DateTime now = DateTime.now();
    if (_playlists == null ||
        _playlistsAt == null ||
        now.difference(_playlistsAt!) > _playlistsTtl) {
      _playlists = await PlaylistRepository.instance.getAllPlaylists();
      _playlistsAt = now;
    }
    for (final Playlist p in _playlists!) {
      if (p.id == playlistId) return p;
    }
    return null;
  }
}
