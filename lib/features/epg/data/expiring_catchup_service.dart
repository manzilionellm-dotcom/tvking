// ============================================================================
//  ExpiringCatchupService — « Bientôt expiré » avec de la VRAIE urgence.
//
//  Principe (Vague 2, décision du propriétaire : jamais de fausse pression) :
//  on n'affiche QUE des comptes à rebours RÉELS. L'archive catch-up d'un
//  panel garde chaque programme `catchupDays` jours après sa diffusion —
//  passé ce délai, il disparaît VRAIMENT. Ici on repère les programmes qui
//  tombent dans les 48 prochaines heures.
//
//  Source de vérité : l'EPG SERVEUR (`get_simple_data_table`, une requête
//  légère PAR chaîne) — l'EPG local purge le passé après 1 h (anti-OOM),
//  il ne peut donc rien savoir de l'archive.
//
//  Garde-fous (box à 30 € et comptes 1-connexion) :
//   • appels API player_api uniquement — JAMAIS une connexion de flux ;
//   • bornés : 4 chaînes max (les plus regardées/favorites), 12 items max ;
//   • cache mémoire 30 min (le rail ne re-frappe pas le panel à chaque
//     rebuild) ; erreurs avalées → rangée simplement absente.
// ============================================================================

import 'dart:convert';

import '../../../core/curation/title_curator.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';

class ExpiringCatchupItem {
  const ExpiringCatchupItem({
    required this.channel,
    required this.title,
    required this.startMs,
    required this.stopMs,
    required this.expiresAtMs,
  });

  final Channel channel;
  final String title;
  final int startMs;
  final int stopMs;

  /// Instant où le programme SORT de l'archive du panel (réel, pas inventé).
  final int expiresAtMs;

  Duration get remaining => Duration(
      milliseconds: expiresAtMs - DateTime.now().millisecondsSinceEpoch);
}

class ExpiringCatchupService {
  ExpiringCatchupService._();

  static final ExpiringCatchupService instance = ExpiringCatchupService._();

  static const Duration _ttl = Duration(minutes: 30);
  static const Duration _window = Duration(hours: 48);
  static const int _maxChannels = 4;
  static const int _maxItems = 12;

  List<ExpiringCatchupItem> _cache = const <ExpiringCatchupItem>[];
  DateTime? _at;
  bool _busy = false;

  /// [affinity] : chaînes classées par intérêt (récents puis favoris) — on
  /// n'interroge que les 4 premières qui supportent le catch-up.
  Future<List<ExpiringCatchupItem>> load(List<Channel> affinity) async {
    final DateTime now = DateTime.now();
    if (_busy) return _cache;
    if (_at != null && now.difference(_at!) < _ttl) return _cache;
    _busy = true;
    try {
      final Playlist? src = _activeXtream();
      if (src == null) {
        _cache = const <ExpiringCatchupItem>[];
        _at = now;
        return _cache;
      }
      final List<Channel> targets = <Channel>[];
      final Set<String> seen = <String>{};
      for (final Channel c in affinity) {
        if (!c.catchupSupported) continue;
        if ((c.catchupDays ?? 0) <= 0) continue;
        if (!c.id.startsWith('xtream-')) continue;
        if (seen.add(c.id)) targets.add(c);
        if (targets.length >= _maxChannels) break;
      }
      if (targets.isEmpty) {
        _cache = const <ExpiringCatchupItem>[];
        _at = now;
        return _cache;
      }
      final XtreamClient client = XtreamClient(
        serverUrl: src.xtreamServer!,
        username: src.xtreamUsername!,
        password: src.xtreamPassword!,
      );
      final List<ExpiringCatchupItem> out = <ExpiringCatchupItem>[];
      final int nowS = now.millisecondsSinceEpoch ~/ 1000;
      try {
        for (final Channel c in targets) {
          try {
            final List<Map<String, dynamic>> rows = await client
                .fetchArchiveTable(c.id.substring('xtream-'.length));
            final int days = c.catchupDays ?? 0;
            for (final Map<String, dynamic> r in rows) {
              if ((r['has_archive']?.toString() ?? '0') != '1') continue;
              final int startS =
                  int.tryParse(r['start_timestamp']?.toString() ?? '') ?? 0;
              final int stopS =
                  int.tryParse(r['stop_timestamp']?.toString() ?? '') ?? 0;
              if (startS <= 0 || stopS <= startS) continue;
              if (stopS >= nowS) continue; // pas encore terminé → pas archive
              final int expiryS = startS + days * 86400;
              final int remS = expiryS - nowS;
              if (remS <= 0 || remS > _window.inSeconds) continue;
              final String title = TitleCurator.curate(_decodeTitle(r['title']));
              if (title.trim().isEmpty) continue;
              out.add(ExpiringCatchupItem(
                channel: c,
                title: title,
                startMs: startS * 1000,
                stopMs: stopS * 1000,
                expiresAtMs: expiryS * 1000,
              ));
            }
          } catch (_) {
            // Chaîne sans data table / panel grognon : on passe.
          }
        }
      } finally {
        client.dispose();
      }
      out.sort((ExpiringCatchupItem a, ExpiringCatchupItem b) =>
          a.expiresAtMs.compareTo(b.expiresAtMs));
      _cache = List<ExpiringCatchupItem>.unmodifiable(
          out.take(_maxItems).toList());
      _at = now;
      return _cache;
    } catch (_) {
      return _cache; // réseau KO → on garde l'existant (ou vide)
    } finally {
      _busy = false;
    }
  }

  Playlist? _activeXtream() {
    Playlist? fallback;
    for (final Playlist p in PlaylistRepository.instance.currentPlaylists) {
      if (p.type != PlaylistType.xtream) continue;
      if (p.xtreamServer == null ||
          p.xtreamUsername == null ||
          p.xtreamPassword == null) {
        continue;
      }
      if (p.isActive) return p;
      fallback ??= p;
    }
    return fallback;
  }

  /// Les titres de `get_simple_data_table` sont souvent en base64 —
  /// décodage TOLÉRANT (sinon on garde le texte brut).
  static String _decodeTitle(dynamic raw) {
    final String s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return s;
    try {
      final String decoded = utf8.decode(base64Decode(s));
      if (decoded.trim().isNotEmpty) return decoded;
    } catch (_) {}
    return s;
  }
}
