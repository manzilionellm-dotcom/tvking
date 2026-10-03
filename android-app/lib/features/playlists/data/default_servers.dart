// =========================================================
//  default_servers.dart — Ancien catalogue, plus affiché
// =========================================================
//  Avant, l'écran de connexion montrait « Serveur 1 », « Serveur 2 »
//  et cachait l'adresse (GET /api/servers). Cet écran n'existe plus :
//  la personne saisit sa propre source (voir open_source_input.dart).
//
//  On GARDE ce fichier pour une migration douce. Une application déjà
//  installée, ou une liste enregistrée avec l'identifiant d'un serveur
//  connu, peut encore retrouver l'adresse via [urlForRegisteredServer]
//  ou via le cache disque. Rien n'est montré dans l'interface.
//
//  Aucune URL de flux n'est écrite en dur ici (règle n°2 d'AGENTS.md).
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

/// Un serveur IPTV par défaut tel que renvoyé par le Worker.
/// Le champ [url] n'est JAMAIS montré au client : il sert seulement
/// en interne à construire les requêtes Xtream.
@immutable
class DefaultServer {
  const DefaultServer({
    required this.id,
    required this.label,
    required this.url,
  });

  /// Identifiant stable (ex. `srv1`). Sert de clé de sélection.
  final String id;

  /// Ancien libellé (« Serveur 1 »). Plus montré. Gardé pour reconnaître
  /// une ligne déjà enregistrée.
  final String label;

  /// Base du serveur Xtream (ex. `http://exemple:8080`). Caché.
  final String url;

  factory DefaultServer.fromJson(Map<String, dynamic> json) {
    return DefaultServer(
      id: (json['id'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'url': url,
      };
}

/// Adresse d'un serveur DÉJÀ enregistré, retrouvée par son identifiant.
/// Sert uniquement en interne : on ne construit pas un menu avec.
/// Inconnu ou adresse vide → null (on n'invente pas de serveur).
String? urlForRegisteredServer(Iterable<DefaultServer> known, String id) {
  final String key = id.trim();
  if (key.isEmpty) return null;
  for (final DefaultServer server in known) {
    if (server.id == key && server.url.trim().isNotEmpty) {
      return server.url.trim();
    }
  }
  return null;
}

abstract final class DefaultServersApi {
  /// Clé du cache SharedPreferences (dernière liste valide connue).
  static const String _kCacheKey = 'default_servers_cache_v1';

  /// Cache mémoire pour éviter de retaper le réseau à chaque
  /// ouverture de l'écran de connexion pendant une session.
  static List<DefaultServer>? _memoryCache;

  /// Récupère la liste des serveurs par défaut.
  ///
  /// Ordre de résolution :
  ///   1. Cache mémoire (si déjà chargé pendant la session).
  ///   2. Réseau (`GET /api/servers`) → met à jour les deux caches.
  ///   3. Cache disque (si le réseau a échoué).
  ///
  /// Ne throw jamais : en dernier recours renvoie une liste vide,
  /// et l'UI affiche un message « serveurs indisponibles, réessaie ».
  static Future<List<DefaultServer>> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) {
      return _memoryCache!;
    }

    final List<DefaultServer>? network = await _fetchFromNetwork();
    if (network != null) {
      _memoryCache = network;
      await _writeCache(network);
      return network;
    }

    // Réseau KO → on retombe sur le dernier cache disque connu.
    final List<DefaultServer> disk = await _readCache();
    _memoryCache = disk;
    return disk;
  }

  static Future<List<DefaultServer>?> _fetchFromNetwork() async {
    try {
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/servers'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[DefaultServers] HTTP ${resp.statusCode}');
        }
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final List<dynamic> raw =
          (body['servers'] as List<dynamic>?) ?? const <dynamic>[];
      final List<DefaultServer> servers = raw
          .whereType<Map<String, dynamic>>()
          .map(DefaultServer.fromJson)
          .where((DefaultServer s) => s.url.isNotEmpty)
          .toList();
      return servers;
    } catch (e) {
      if (kDebugMode) debugPrint('[DefaultServers] fetch error: $e');
      return null;
    }
  }

  static Future<void> _writeCache(List<DefaultServer> servers) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheKey,
        jsonEncode(servers.map((DefaultServer s) => s.toJson()).toList()),
      );
    } catch (_) {
      // Cache best-effort : pas grave si l'écriture échoue.
    }
  }

  static Future<List<DefaultServer>> _readCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return const <DefaultServer>[];
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(DefaultServer.fromJson)
          .where((DefaultServer s) => s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const <DefaultServer>[];
    }
  }
}
