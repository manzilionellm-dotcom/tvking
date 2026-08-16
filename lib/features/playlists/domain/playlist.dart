// =========================================================
//  playlist.dart — Modèle "Playlist IPTV"
// =========================================================
//  Une playlist = une source de chaînes. Trois types prévus :
//    - M3U (URL vers un fichier .m3u/.m3u8)
//    - Xtream (serveur + login + mot de passe)
//    - (Phase ultérieure) MAG / Portal Stalker
//
//  Pour rester simple en Phase 1, on encode le type sous forme
//  d'enum + champs optionnels selon le type. Quand on ajoutera
//  Drift/Riverpod plus tard, on pourra passer à des classes
//  sealed Dart 3 pour plus de propreté.
// =========================================================

import 'package:flutter/material.dart';

enum PlaylistType {
  m3u,
  xtream,
}

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.m3uUrl,
    this.xtreamServer,
    this.xtreamUsername,
    this.xtreamPassword,
    this.epgUrl,
    this.lastSyncedAt,
    this.channelCount = 0,
    this.isActive = false,
  });

  /// ID auto-incrémenté par SQLite. Null = pas encore enregistrée.
  final int? id;

  /// Nom donné par l'utilisateur (ex : "Mon abonnement").
  final String name;

  /// Type de playlist (M3U ou Xtream).
  final PlaylistType type;

  /// Date d'ajout (timestamp ms epoch).
  final int createdAt;

  /// URL du fichier .m3u (uniquement si type == m3u).
  final String? m3uUrl;

  /// URL du serveur Xtream avec port (ex: "http://server.com:8080").
  final String? xtreamServer;

  /// Identifiant Xtream.
  final String? xtreamUsername;

  /// Mot de passe Xtream (stocké en clair pour l'instant ;
  /// Phase 5 on chiffrera avec flutter_secure_storage).
  final String? xtreamPassword;

  /// URL XMLTV pour l'EPG (optionnel — pour Xtream l'EPG vient
  /// automatiquement via xmltv.php).
  final String? epgUrl;

  /// Dernière synchronisation réussie (null = jamais).
  final int? lastSyncedAt;

  /// Nombre de chaînes après la dernière sync.
  final int channelCount;

  /// Phase 1+/Multi-serveurs (2026-06-01) : indique si cette playlist
  /// est la source de chaines active pour l'app. Un seul `true` a la
  /// fois — la repo garantit l'exclusivite via [setActive]. Quand
  /// false, ses chaines existent en base mais ne sont pas exposees
  /// par [PlaylistRepository.getAllChannels].
  final bool isActive;

  // ---------- Sérialisation SQLite ----------

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'type': type.name,
      'm3u_url': m3uUrl,
      'xtream_server': xtreamServer,
      'xtream_username': xtreamUsername,
      'xtream_password': xtreamPassword,
      'epg_url': epgUrl,
      'created_at': createdAt,
      'last_synced_at': lastSyncedAt,
      'channel_count': channelCount,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Playlist.fromMap(Map<String, Object?> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: PlaylistType.values.firstWhere(
        (PlaylistType t) => t.name == (map['type'] as String),
        orElse: () => PlaylistType.m3u,
      ),
      createdAt: map['created_at'] as int,
      m3uUrl: map['m3u_url'] as String?,
      xtreamServer: map['xtream_server'] as String?,
      xtreamUsername: map['xtream_username'] as String?,
      xtreamPassword: map['xtream_password'] as String?,
      epgUrl: map['epg_url'] as String?,
      lastSyncedAt: map['last_synced_at'] as int?,
      channelCount: (map['channel_count'] as int?) ?? 0,
      isActive: (map['is_active'] as int?) == 1,
    );
  }

  Playlist copyWith({
    int? id,
    int? lastSyncedAt,
    int? channelCount,
    bool? isActive,
    // Identifiants corrigés depuis le panel (mot de passe renouvelé).
    String? xtreamPassword,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name,
      type: type,
      createdAt: createdAt,
      m3uUrl: m3uUrl,
      xtreamServer: xtreamServer,
      xtreamUsername: xtreamUsername,
      xtreamPassword: xtreamPassword ?? this.xtreamPassword,
      epgUrl: epgUrl,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      channelCount: channelCount ?? this.channelCount,
      isActive: isActive ?? this.isActive,
    );
  }
}
