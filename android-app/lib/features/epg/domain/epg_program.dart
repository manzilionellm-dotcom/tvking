// =========================================================
//  epg_program.dart — Modèle "Programme TV" (EPG)
// =========================================================
//  Un programme = une émission diffusée sur une chaîne entre
//  deux instants. Vient d'un fichier XMLTV ou de l'API Xtream.
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.startTime,
    required this.stopTime,
    required this.title,
    this.description,
    this.category,
    this.iconUrl,
  });

  /// ID de la chaîne (correspond à `Channel.id`, typiquement tvg-id M3U).
  final String channelId;

  /// Début et fin du programme (millisecondes epoch UTC).
  final int startTime;
  final int stopTime;

  /// Titre affiché ("Le Grand Journal").
  final String title;

  /// Description longue (optionnelle).
  final String? description;

  /// Genre/catégorie ("News", "Documentary", "Movie"...).
  final String? category;

  /// Vignette du programme (optionnelle).
  final String? iconUrl;

  // ----- Helpers -----

  DateTime get startDateTime =>
      DateTime.fromMillisecondsSinceEpoch(startTime);
  DateTime get stopDateTime =>
      DateTime.fromMillisecondsSinceEpoch(stopTime);

  Duration get duration => Duration(milliseconds: stopTime - startTime);

  bool isLiveAt(DateTime moment) {
    final int ms = moment.millisecondsSinceEpoch;
    return startTime <= ms && ms < stopTime;
  }

  /// "20h00 - 21h30"
  String get timeRangeShort {
    String two(int n) => n.toString().padLeft(2, '0');
    final DateTime s = startDateTime;
    final DateTime e = stopDateTime;
    return '${two(s.hour)}h${two(s.minute)} – ${two(e.hour)}h${two(e.minute)}';
  }

  /// "90 min"
  String get durationLabel {
    final int minutes = duration.inMinutes;
    if (minutes >= 60) {
      final int h = minutes ~/ 60;
      final int m = minutes % 60;
      return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
    }
    return '${minutes}min';
  }

  // ----- Sérialisation SQLite -----

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'channel_id': channelId,
      'start_time': startTime,
      'stop_time': stopTime,
      'title': title,
      'description': description,
      'category': category,
      'icon_url': iconUrl,
    };
  }

  factory EpgProgram.fromMap(Map<String, Object?> map) {
    return EpgProgram(
      channelId: map['channel_id'] as String,
      startTime: map['start_time'] as int,
      stopTime: map['stop_time'] as int,
      title: map['title'] as String,
      description: map['description'] as String?,
      category: map['category'] as String?,
      iconUrl: map['icon_url'] as String?,
    );
  }
}
