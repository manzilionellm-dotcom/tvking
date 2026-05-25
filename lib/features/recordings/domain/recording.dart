// =========================================================
//  recording.dart — Modèle d'un enregistrement local
// =========================================================
//  Métadonnées d'un fichier .ts capturé par libmpv via la
//  propriété `stream-record`. Stocké en SQLite.
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
  });

  final int? id;
  final String channelId;
  final String channelName;
  final String? programTitle;
  final String filePath;
  final int startedAt;
  final int? endedAt;
  final int fileSizeBytes;

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
    );
  }

  Recording copyWith({
    int? id,
    int? endedAt,
    int? fileSizeBytes,
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
    );
  }
}
