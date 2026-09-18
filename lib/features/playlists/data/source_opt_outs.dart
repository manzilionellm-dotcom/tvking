// =========================================================
//  source_opt_outs.dart — Suppressions VOLONTAIRES de sources
// =========================================================
//  Retour client (21/08) : « si je supprime l'abonnement, ça doit être
//  supprimé carrément — au redémarrage il est toujours là, c'est pas
//  professionnel. » La cause : la PROVISION AUTOMATIQUE par MAC
//  (RemoteSourceRepository.sync) re-importait au boot la source que le
//  client venait de supprimer localement.
//
//  Ici : on mémorise l'« empreinte » de chaque source supprimée PAR UN
//  GESTE VOLONTAIRE (écran Sources TV/téléphone, ou ordre du panel).
//  La provision automatique la SAUTE tant que l'empreinte est posée.
//
//  RÉCUPÉRATION (suppression par accident) : quand le revendeur POUSSE à
//  nouveau depuis le panel (temps réel → signalPushed), les empreintes
//  sont TOUTES levées — un geste délibéré du panel gagne toujours.
//  « Contacte ton revendeur, il peut te la remettre » : exactement le
//  parcours voulu par le propriétaire.
//
//  Best-effort de bout en bout : préférences illisibles → aucune entrave
//  (on préfère re-provisionner une fois de trop que bloquer un client).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';

abstract final class SourceOptOuts {
  static const String _kKey = 'remote.source.optout.v1';

  static String _fpXtream(String server, String user) =>
      'x|${server.trim()}|${user.trim()}';
  static String _fpM3u(String url) => 'm|${url.trim()}';

  /// Empreinte d'une playlist locale (null = type inconnu, rien à poser).
  static String? _fpOf(Playlist p) {
    if (p.type == PlaylistType.xtream) {
      return _fpXtream(p.xtreamServer ?? '', p.xtreamUsername ?? '');
    }
    if (p.type == PlaylistType.m3u) return _fpM3u(p.m3uUrl ?? '');
    return null;
  }

  /// Pose l'empreinte d'une source supprimée VOLONTAIREMENT.
  static Future<void> markDeleted(Playlist p) async {
    final String? fp = _fpOf(p);
    if (fp == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Set<String> all =
          (prefs.getStringList(_kKey) ?? const <String>[]).toSet()..add(fp);
      await prefs.setStringList(_kKey, all.toList());
      if (kDebugMode) debugPrint('[OptOut] posé : $fp');
    } catch (_) {
      // best-effort — au pire la source revient une fois de plus.
    }
  }

  /// La provision automatique doit-elle SAUTER cette source Xtream ?
  static Future<bool> isXtreamOptedOut(String server, String user) =>
      _contains(_fpXtream(server, user));

  /// La provision automatique doit-elle SAUTER cette source M3U ?
  static Future<bool> isM3uOptedOut(String url) => _contains(_fpM3u(url));

  static Future<bool> _contains(String fp) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_kKey) ?? const <String>[]).contains(fp);
    } catch (_) {
      return false; // en cas de doute : ne jamais bloquer une provision
    }
  }

  /// Lève TOUTES les empreintes — appelé quand le panel POUSSE une source
  /// en temps réel (geste délibéré du revendeur = récupération).
  static Future<void> clearAll() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
      if (kDebugMode) debugPrint('[OptOut] tout levé (push panel)');
    } catch (_) {
      // best-effort.
    }
  }
}
