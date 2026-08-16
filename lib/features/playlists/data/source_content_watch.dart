// ============================================================================
//  SourceContentWatch — resynchronisation AUTOMATIQUE du contenu panel.
//
//  BUG TERRAIN (photo client, box réelle) : le revendeur retire des bouquets
//  dans le panel (ex. « je supprime tous les pays, je garde la France ») et
//  la box continue d'afficher l'ANCIEN contenu (la Belgique reste là) tant
//  que le client ne fait pas un « rafraîchir » MANUEL — que les clients ne
//  connaissent pas. `RemoteSourceRepository.sync()` (5 min) ne corrige pas
//  ça : il n'AJOUTE que les sources manquantes, il ne re-importe JAMAIS le
//  contenu d'une source déjà chargée.
//
//  ICI : toutes les 60 s, pour chaque source Xtream chargée, on demande au
//  panel la liste des catégories Live (`get_live_categories` — UNE requête
//  JSON minuscule, PAS le million de chaînes). On en calcule une empreinte
//  (FNV-1a). Si l'empreinte a changé depuis la dernière fois → le panel a
//  bougé → on déclenche le MÊME `refreshPlaylist()` que le bouton manuel
//  (remplace les chaînes en base + ré-émet sur le stream → l'UI se met à
//  jour toute seule, sans redémarrage, sans action client).
//
//  Garde-fous :
//   • 1re observation = on STOCKE l'empreinte, on ne rafraîchit PAS
//     (sinon chaque boot déclencherait un re-import complet inutile) ;
//   • `_busy` : jamais deux passes en parallèle (un refresh peut durer) ;
//   • silencieux : toute erreur réseau/panel est avalée — le tick suivant
//     retentera ; AUCUN impact visible si le panel est injoignable ;
//   • sources M3U : ignorées en v1 (pas d'endpoint « catégories » léger ;
//     re-télécharger le .m3u entier chaque minute serait abusif).
// ============================================================================

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';
import 'playlist_repository.dart';
import 'xtream_client.dart';

class SourceContentWatch {
  SourceContentWatch._();

  static final SourceContentWatch instance = SourceContentWatch._();

  static const Duration _interval = Duration(minutes: 1);
  static const String _fpKeyPrefix = 'src_watch_fp_';

  Timer? _timer;
  bool _busy = false;

  /// Démarre la surveillance (idempotent — un seul timer, appels
  /// multiples sans effet).
  ///
  /// [every] permet d'adapter la cadence au support : 1 min sur BOX (branchée
  /// au secteur, allumée en continu, le client veut du « instantané »),
  /// 5 min sur TÉLÉPHONE — une requête par minute sur batterie ne se
  /// justifie pas pour un appareil qu'on n'utilise que par sessions.
  void start({Duration? every}) {
    _timer ??= Timer.periodic(every ?? _interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final List<Playlist> playlists =
          List<Playlist>.of(PlaylistRepository.instance.currentPlaylists);
      if (playlists.isEmpty) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final Playlist p in playlists) {
        if (p.type != PlaylistType.xtream) continue;
        if (p.id == null) continue;
        final String? server = p.xtreamServer;
        final String? user = p.xtreamUsername;
        final String? pass = p.xtreamPassword;
        if (server == null || user == null || pass == null) continue;
        await _checkOne(prefs, p, server, user, pass);
      }
    } catch (_) {
      // Silencieux : le tick suivant retentera.
    } finally {
      _busy = false;
    }
  }

  Future<void> _checkOne(
    SharedPreferences prefs,
    Playlist p,
    String server,
    String user,
    String pass,
  ) async {
    final XtreamClient client = XtreamClient(
      serverUrl: server,
      username: user,
      password: pass,
    );
    try {
      final Map<String, String> cats = await client.fetchLiveCategories();
      // Empreinte STABLE : entrées `id=nom` triées puis hachées — l'ordre
      // renvoyé par le panel peut varier sans que le contenu change.
      final List<String> entries =
          cats.entries.map((e) => '${e.key}=${e.value}').toList()..sort();
      final String fp = _fnv1a(entries.join('|'));
      final String key = '$_fpKeyPrefix${p.id}';
      final String? previous = prefs.getString(key);
      if (previous == null) {
        // 1re observation : on mémorise, pas de refresh.
        await prefs.setString(key, fp);
        return;
      }
      if (previous == fp) return; // rien n'a bougé
      // Le panel a changé → même chemin que le bouton « rafraîchir »
      // manuel : remplace les chaînes + ré-émet le stream → UI à jour.
      final bool ok = await PlaylistRepository.instance.refreshPlaylist(p);
      if (ok) await prefs.setString(key, fp);
    } catch (_) {
      // Panel injoignable / réponse cassée : on garde l'ancienne
      // empreinte et on réessaiera au tick suivant.
    } finally {
      client.dispose();
    }
  }

  /// FNV-1a 64 bits (hex) — rapide, sans dépendance, largement suffisant
  /// pour détecter « la liste de catégories a changé ».
  static String _fnv1a(String input) {
    int hash = 0xcbf29ce484222325;
    for (final int unit in input.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(60).toRadixString(16);
  }
}
