// =========================================================
//  default_servers.dart — Serveurs IPTV par défaut (côté serveur)
// =========================================================
//  L'app NE contient AUCUNE URL de flux IPTV en dur : c'est la
//  règle n°2 non-négociable d'AGENTS.md. À la place, on récupère
//  la liste des serveurs proposés (« Serveur 1 », « Serveur 2 »…)
//  depuis le Worker Cloudflare via `GET /api/servers`.
//
//  Conséquence : le client ne tape jamais d'URL. Il choisit un
//  serveur dans la liste et saisit seulement son code Xtream
//  (utilisateur + mot de passe). L'URL réelle reste cachée côté
//  serveur et peut être changée sans re-publier l'app (il suffit
//  de modifier la variable `DEFAULT_SERVERS` du Worker).
//
//  Robustesse :
//    - On met en cache la dernière liste valide dans
//      SharedPreferences. Si le Worker est injoignable au prochain
//      démarrage (WiFi en creux), on ressert la liste connue plutôt
//      que de laisser le client sans aucun serveur.
//    - Timeout court (8 s) pour ne pas figer l'écran de connexion.
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

  /// Libellé affiché au client (ex. « Serveur 1 »). C'est la SEULE
  /// chose visible — l'URL reste cachée.
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
