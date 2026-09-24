// =========================================================
//  recording.dart — Modèle d'un enregistrement local
// =========================================================
//  Métadonnées d'un fichier .ts capturé par le downloader HTTP
//  Dart pur (cf. data/http_recording_downloader.dart). Stocké en SQLite.
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class Recording {
  const Recording({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.filePath,
    required this.startedAt,
    this.programTitle,
    this.endedAt,
    this.fileSizeBytes = 0,
    this.channelLogoUrl,
    this.streamUrl,
    this.autoStopReason,
  });

  final int? id;
  final String channelId;
  final String channelName;
  final String? programTitle;
  final String filePath;
  final int startedAt;
  final int? endedAt;
  final int fileSizeBytes;
  /// URL du logo de la chaîne au moment de l'enregistrement — utilisée
  /// pour afficher le logo en overlay flottant lors de la relecture
  /// (style "France 2 en bas-droite"). Null pour les anciens enregistrements
  /// faits avant l'ajout de cette colonne.
  final String? channelLogoUrl;

  /// Phase 1 / F-04 : URL upstream du flux IPTV au moment du start.
  /// Persistee pour pouvoir, plus tard, implementer un "resume apres
  /// kill OS" (Phase 2+ — non implemente en Phase 1). Aussi utile pour
  /// le diagnostic : un user peut nous dire "ce recording a planté"
  /// et on saura quelle URL retesteer. Null pour les anciens
  /// enregistrements faits avant la migration.
  final String? streamUrl;

  /// Phase 1 / F-03 : motif d'arret automatique, persiste a la
  /// finalisation. Valeurs canoniques (cf.
  /// http_recording_downloader.dart `AutoStopReason`) :
  ///   - `maxDurationReached`
  ///   - `serverUnreachable`
  ///   - `diskError`
  ///   - `interruptedByOsKill`   (recovere via recoverOrphans, F-01)
  ///   - `null`                  (stop volontaire utilisateur ou ancien)
  final String? autoStopReason;

  Duration get duration {
    final int end = endedAt ?? DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: end - startedAt);
  }

  String get durationLabel {
    final int minutes = duration.inMinutes;
    if (minutes >= 60) {
      final int h = minutes ~/ 60;
      final int m = minutes % 60;
      return m == 0
          ? '${h}h'
          : '${h}h${m.toString().padLeft(2, '0')}';
    }
    return '$minutes min';
  }

  String get sizeLabel {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} Ko';
    }
    if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Go';
  }

  String get startedLabel {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(startedAt);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} à ${two(dt.hour)}h${two(dt.minute)}';
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'channel_id': channelId,
      'channel_name': channelName,
      'program_title': programTitle,
      'file_path': filePath,
      'started_at': startedAt,
      'ended_at': endedAt,
      'file_size_bytes': fileSizeBytes,
      'channel_logo_url': channelLogoUrl,
      'stream_url': streamUrl,
      'auto_stop_reason': autoStopReason,
    };
  }

  factory Recording.fromMap(Map<String, Object?> map) {
    return Recording(
      id: map['id'] as int?,
      channelId: map['channel_id'] as String,
      channelName: map['channel_name'] as String,
      programTitle: map['program_title'] as String?,
      filePath: map['file_path'] as String,
      startedAt: map['started_at'] as int,
      endedAt: map['ended_at'] as int?,
      fileSizeBytes: (map['file_size_bytes'] as int?) ?? 0,
      channelLogoUrl: map['channel_logo_url'] as String?,
      streamUrl: map['stream_url'] as String?,
      autoStopReason: map['auto_stop_reason'] as String?,
    );
  }

  Recording copyWith({
    int? id,
    int? endedAt,
    int? fileSizeBytes,
    String? autoStopReason,
  }) {
    return Recording(
      id: id ?? this.id,
      channelId: channelId,
      channelName: channelName,
      programTitle: programTitle,
      filePath: filePath,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      channelLogoUrl: channelLogoUrl,
      streamUrl: streamUrl,
      autoStopReason: autoStopReason ?? this.autoStopReason,
    );
  }
}
