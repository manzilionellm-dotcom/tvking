// =========================================================
//  scheduled_recording.dart — Modèle d'un enregistrement PROGRAMMÉ
// =========================================================
//  « Enregistre Koh-Lanta ce soir à 21 h 10 » : on mémorise l'émission
//  (chaîne, titre, horaires), un fichier de destination et un STATUT qui
//  évolue : prévu → en cours → terminé (ou manqué / échec / annulé).
//
//  Le flux lui-même est capté soit par le natif Android (alarme exacte +
//  service au premier plan, survit à la veille de la box), soit par le
//  téléchargeur Dart quand le natif n'existe pas (Windows, Tizen…).
//  Dart pur : aucune dépendance Flutter, sérialisable en SQLite.
// =========================================================

import 'package:flutter/foundation.dart';

/// Cycle de vie d'une programmation.
enum ScheduledRecordingStatus {
  /// Créneau à venir, alarmes posées.
  planned,

  /// Capture en cours (natif ou Dart).
  recording,

  /// Fichier écrit et fiche créée dans « Mes enregistrements ».
  done,

  /// Le créneau est passé sans qu'aucune capture n'ait démarré (app et
  /// box éteintes, alarme jamais reçue…).
  missed,

  /// Démarrage ou capture en erreur (espace disque, refus Android, flux
  /// mort dès le début). Le détail est dans [ScheduledRecording.error].
  failed,

  /// Annulé par le client.
  cancelled,
}

@immutable
class ScheduledRecording {
  const ScheduledRecording({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.streamUrl,
    required this.startMs,
    required this.stopMs,
    required this.filePath,
    required this.createdAt,
    this.programTitle,
    this.channelLogoUrl,
    this.marginBeforeMs = defaultMarginBeforeMs,
    this.marginAfterMs = defaultMarginAfterMs,
    this.status = ScheduledRecordingStatus.planned,
    this.recordingId,
    this.bytes = 0,
    this.error,
  });

  /// Marge AVANT le début officiel : les guides ont souvent 1-2 min de
  /// retard, et une alarme inexacte peut glisser. 2 min = filet raisonnable.
  static const int defaultMarginBeforeMs = 2 * 60 * 1000;

  /// Marge APRÈS la fin officielle : les émissions débordent (pub, prolongations).
  static const int defaultMarginAfterMs = 5 * 60 * 1000;

  /// Identifiant stable : `<hash chaîne>-<début>` → reprogrammer la même
  /// émission remplace l'entrée au lieu de la dupliquer.
  static String idFor(String channelId, int startMs) =>
      '${channelId.hashCode & 0x7fffffff}-$startMs';

  final String id;
  final String channelId;
  final String channelName;
  final String? channelLogoUrl;
  final String streamUrl;
  final String? programTitle;

  /// Début / fin OFFICIELS de l'émission (epoch ms). Les marges s'ajoutent
  /// par-dessus (cf. [effectiveStartMs] / [effectiveStopMs]).
  final int startMs;
  final int stopMs;
  final int marginBeforeMs;
  final int marginAfterMs;

  /// Fichier de destination (.ts), fixé à la programmation.
  final String filePath;
  final int createdAt;
  final ScheduledRecordingStatus status;

  /// Id de la fiche `recordings` une fois la capture démarrée (null avant).
  final int? recordingId;

  /// Octets écrits (mis à jour à la fin, ou en direct côté natif).
  final int bytes;

  /// Code d'erreur court (ex. `noSpace`, `busy`, `fgsDenied`, `tooLate`).
  final String? error;

  int get effectiveStartMs => startMs - marginBeforeMs;
  int get effectiveStopMs => stopMs + marginAfterMs;

  DateTime get startDateTime => DateTime.fromMillisecondsSinceEpoch(startMs);
  DateTime get stopDateTime => DateTime.fromMillisecondsSinceEpoch(stopMs);
  Duration get duration => Duration(milliseconds: stopMs - startMs);

  bool get isActive =>
      status == ScheduledRecordingStatus.planned ||
      status == ScheduledRecordingStatus.recording;

  /// Deux programmations se chevauchent si leurs créneaux EFFECTIFS
  /// (marges comprises) ont une intersection non vide. Une ligne IPTV
  /// n'ayant en général qu'une connexion, on refuse le chevauchement
  /// sauf si c'est la MÊME chaîne (le tee partage la connexion).
  bool overlaps(ScheduledRecording other) {
    if (other.id == id) return false;
    return effectiveStartMs < other.effectiveStopMs &&
        other.effectiveStartMs < effectiveStopMs;
  }

  ScheduledRecording copyWith({
    ScheduledRecordingStatus? status,
    int? recordingId,
    int? bytes,
    String? error,
    bool clearError = false,
  }) {
    return ScheduledRecording(
      id: id,
      channelId: channelId,
      channelName: channelName,
      channelLogoUrl: channelLogoUrl,
      streamUrl: streamUrl,
      programTitle: programTitle,
      startMs: startMs,
      stopMs: stopMs,
      marginBeforeMs: marginBeforeMs,
      marginAfterMs: marginAfterMs,
      filePath: filePath,
      createdAt: createdAt,
      status: status ?? this.status,
      recordingId: recordingId ?? this.recordingId,
      bytes: bytes ?? this.bytes,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'channel_id': channelId,
        'channel_name': channelName,
        'channel_logo_url': channelLogoUrl,
        'stream_url': streamUrl,
        'program_title': programTitle,
        'start_ms': startMs,
        'stop_ms': stopMs,
        'margin_before_ms': marginBeforeMs,
        'margin_after_ms': marginAfterMs,
        'file_path': filePath,
        'created_at': createdAt,
        'status': status.name,
        'recording_id': recordingId,
        'bytes': bytes,
        'error': error,
      };

  factory ScheduledRecording.fromMap(Map<String, Object?> m) {
    final String st = (m['status'] as String?) ?? 'planned';
    return ScheduledRecording(
      id: m['id'] as String,
      channelId: m['channel_id'] as String,
      channelName: m['channel_name'] as String,
      channelLogoUrl: m['channel_logo_url'] as String?,
      streamUrl: m['stream_url'] as String,
      programTitle: m['program_title'] as String?,
      startMs: m['start_ms'] as int,
      stopMs: m['stop_ms'] as int,
      marginBeforeMs: (m['margin_before_ms'] as int?) ?? defaultMarginBeforeMs,
      marginAfterMs: (m['margin_after_ms'] as int?) ?? defaultMarginAfterMs,
      filePath: m['file_path'] as String,
      createdAt: (m['created_at'] as int?) ?? 0,
      status: ScheduledRecordingStatus.values.firstWhere(
        (ScheduledRecordingStatus s) => s.name == st,
        orElse: () => ScheduledRecordingStatus.planned,
      ),
      recordingId: m['recording_id'] as int?,
      bytes: (m['bytes'] as int?) ?? 0,
      error: m['error'] as String?,
    );
  }
}
