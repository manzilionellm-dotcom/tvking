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

  /// Programmes à venir de [channel] via `get_short_epg`. `[]` si la chaîne
  /// n'est pas Xtream, si sa playlist n'a plus d'identifiants, ou si le
  /// panel ne répond rien d'exploitable.
  Future<List<EpgProgram>> upcomingFor(Channel channel) async {
    final String? streamId = _xtreamStreamId(channel.id);
    if (streamId == null) return const <EpgProgram>[];

    final ({DateTime at, List<EpgProgram> programs})? hit = _cache[channel.id];
    if (hit != null && DateTime.now().difference(hit.at) <= _ttl) {
      return hit.programs;
    }

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
    final List<Playlist> all =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in all) {
      if (p.id == playlistId) return p;
    }
    return null;
  }
}
