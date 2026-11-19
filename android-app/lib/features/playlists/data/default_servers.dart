// =========================================================
//  default_servers.dart — Choix facultatif de serveurs du panel
// =========================================================
//  Le client peut choisir une adresse configurée par l'administrateur
//  ou écrire la sienne. Le choix remplit le champ URL visible ; il ne
//  connecte rien et ne remplace jamais une liste déjà enregistrée.
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
/// L'adresse reste visible et modifiable avant la connexion Xtream.
@immutable
class DefaultServer {
  const DefaultServer({
    required this.id,
    required this.label,
    required this.url,
  });

  /// Identifiant stable (ex. `srv1`). Sert de clé de sélection.
  final String id;

  /// Libellé configuré dans le panel.
  final String label;

  /// Base du serveur Xtream, sans identifiants préremplis.
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
  static Future<List<DefaultServer>>? _pending;
  static final ValueNotifier<List<DefaultServer>> current =
      ValueNotifier<List<DefaultServer>>(const <DefaultServer>[]);

  /// Récupère la liste des serveurs par défaut.
  ///
  /// Ordre de résolution :
  ///   1. Cache mémoire (si déjà chargé pendant la session).
  ///   2. Réseau (`GET /api/servers`) → met à jour les deux caches.
  ///   3. Cache disque (si le réseau a échoué).
  ///
  /// Pour l'UI, une panne conserve le cache ou une liste vide. Le mode strict
  /// propage au contraire l'échec de sa nouvelle lecture pour l'ACK du panel.
  static Future<List<DefaultServer>> fetch(
      {bool forceRefresh = false, bool strict = false}) async {
    if (!forceRefresh && !strict && _memoryCache != null) {
      return _memoryCache!;
    }

    // Une lecture partie avant l'ordre peut encore contenir l'ancienne valeur.
    // Le strict attend sa fin, puis démarre sa propre lecture après l'ordre.
    // La boucle sérialise aussi plusieurs ordres stricts sans réponse tardive.
    if (strict) {
      while (_pending != null) {
        final previous = _pending!;
        try {
          await previous;
        } catch (_) {
          // Seule la nouvelle lecture décide du succès de cet ordre.
        }
        if (identical(_pending, previous)) _pending = null;
      }
    }
    final pending = _pending ??= _refresh();
    try {
      return await pending;
    } catch (_) {
      if (strict) rethrow;
      final disk = _memoryCache ?? await _readCache();
      _memoryCache ??= disk;
      current.value = _memoryCache!;
      return _memoryCache!;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  static Future<List<DefaultServer>> _refresh() async {
    final servers = await _fetchFromNetwork();
    await _writeCache(servers);
    _memoryCache = servers;
    current.value = servers;
    return servers;
  }

  static Future<List<DefaultServer>> _fetchFromNetwork() async {
    try {
      final http.Response resp = await http.get(
        Uri.parse('$kSubscriptionBaseUrl/api/servers'),
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        throw StateError('Catalogue distant non confirmé');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Catalogue distant invalide');
      }
      final body = decoded;
      if (body['servers'] is! List ||
          (body['servers'] as List)
              .any((row) => row is! Map<String, dynamic>)) {
        throw const FormatException('Catalogue distant invalide');
      }
      final List<dynamic> raw =
          (body['servers'] as List<dynamic>?) ?? const <dynamic>[];
      return _parseServers(raw);
    } catch (e) {
      if (kDebugMode)
        debugPrint('[DefaultServers] fetch error: ${e.runtimeType}');
      rethrow;
    }
  }

  static List<DefaultServer> _parseServers(List<dynamic> rows) {
    final ids = <String>{};
    final result = <DefaultServer>[];
    for (final row in rows.take(100)) {
      if (row is! Map<String, dynamic> ||
          row['enabled'] == false ||
          row['enabled'] == 0) continue;
      final item = DefaultServer.fromJson(row);
      final uri = Uri.tryParse(item.url);
      if (item.id.isEmpty ||
          !ids.add(item.id) ||
          uri == null ||
          !<String>['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) continue;
      result.add(item);
    }
    return List<DefaultServer>.unmodifiable(result);
  }

  @visibleForTesting
  static void resetForTesting() {
    _memoryCache = null;
    _pending = null;
    current.value = const <DefaultServer>[];
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
      return _parseServers(list);
    } catch (_) {
      return const <DefaultServer>[];
    }
  }
}
