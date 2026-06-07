// =========================================================
//  admin_client.dart — Modèle "Client" côté admin
// =========================================================
//  Représente une entrée du JSON de provisioning, vue depuis
//  le dashboard admin. Un client = une MAC + une liste de
//  playlists qui lui sont assignées.
//
//  Structure JSON correspondante (par client) :
//
//    "MK:AA:BB:CC:DD:EE": {
//      "name": "Lionel",                    ← optionnel (admin only)
//      "added_at": 1716659400000,           ← optionnel (admin only)
//      "playlists": [
//        {
//          "name": "Mon abo",
//          "type": "m3u",
//          "url": "http://serveur/get.php?…",
//          "epg_url": "http://serveur/xmltv.php?…"
//        },
//        {
//          "name": "Test xtream",
//          "type": "xtream",
//          "server": "http://srv:8080",
//          "username": "user",
//          "password": "pass"
//        }
//      ]
//    }
//
//  Les champs `name` et `added_at` ne sont PAS utilisés par
//  l'app cliente (le RemoteConfigRepository les ignore). Ils
//  servent uniquement à l'admin pour identifier ses clients.
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class AdminClient {
  const AdminClient({
    required this.mac,
    required this.name,
    required this.addedAt,
    required this.playlists,
  });

  final String mac;
  final String name; // libellé humain (vide si pas renseigné)
  final int? addedAt; // ms epoch quand l'admin l'a ajouté
  final List<AdminPlaylist> playlists;

  AdminClient copyWith({
    String? mac,
    String? name,
    int? addedAt,
    List<AdminPlaylist>? playlists,
  }) {
    return AdminClient(
      mac: mac ?? this.mac,
      name: name ?? this.name,
      addedAt: addedAt ?? this.addedAt,
      playlists: playlists ?? this.playlists,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (name.isNotEmpty) 'name': name,
      if (addedAt != null) 'added_at': addedAt,
      'playlists': playlists.map((AdminPlaylist p) => p.toJson()).toList(),
    };
  }

  factory AdminClient.fromJson(String mac, Map<String, dynamic> json) {
    final List<dynamic> rawPlaylists =
        (json['playlists'] as List<dynamic>?) ?? const <dynamic>[];
    return AdminClient(
      mac: mac,
      name: (json['name'] as String?) ?? '',
      addedAt: json['added_at'] as int?,
      playlists: rawPlaylists
          .whereType<Map<String, dynamic>>()
          .map(AdminPlaylist.fromJson)
          .toList(),
    );
  }
}

@immutable
class AdminPlaylist {
  const AdminPlaylist({
    required this.name,
    required this.type,
    this.url,
    this.epgUrl,
    this.server,
    this.username,
    this.password,
  });

  /// `'m3u'` ou `'xtream'`. On garde une String et non un enum pour
  /// rester aligné avec le format JSON du provisioning.
  final String type;
  final String name;

  // ---- M3U ----
  final String? url;
  final String? epgUrl;

  // ---- Xtream ----
  final String? server;
  final String? username;
  final String? password;

  bool get isM3u => type == 'm3u';
  bool get isXtream => type == 'xtream';

  AdminPlaylist copyWith({
    String? name,
    String? type,
    String? url,
    String? epgUrl,
    String? server,
    String? username,
    String? password,
  }) {
    return AdminPlaylist(
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      epgUrl: epgUrl ?? this.epgUrl,
      server: server ?? this.server,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'type': type,
      if (url != null && url!.isNotEmpty) 'url': url,
      if (epgUrl != null && epgUrl!.isNotEmpty) 'epg_url': epgUrl,
      if (server != null && server!.isNotEmpty) 'server': server,
      if (username != null && username!.isNotEmpty) 'username': username,
      if (password != null && password!.isNotEmpty) 'password': password,
    };
  }

  factory AdminPlaylist.fromJson(Map<String, dynamic> json) {
    return AdminPlaylist(
      name: (json['name'] as String?) ?? 'Sans nom',
      type: (json['type'] as String?) ?? 'm3u',
      url: json['url'] as String?,
      epgUrl: json['epg_url'] as String?,
      server: json['server'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
    );
  }
}
