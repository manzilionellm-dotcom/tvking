// =========================================================
//  cast_session_diagnostic.dart — Télémétrie d'une session de cast
// =========================================================
//  On capture tout ce qui s'est passé pendant un castTo() pour
//  pouvoir le réutiliser :
//
//    - Dans l'écran Diagnostic (CastDiagnosticsScreen) qui empile
//      les résultats côte-à-côte pour identifier visuellement les
//      patterns d'échec.
//    - Dans un rapport JSON copiable que le testeur colle dans
//      une issue GitHub.
//    - Pour repérer post-mortem quel device/stream/strategy combo
//      casse en prod (on garde les 20 dernières sessions en RAM).
//
//  Le champ critique = `attempts` : la liste ordonnée des essais
//  de la ladder (direct / relay+full / relay+minimal) avec leur
//  résultat individuel. C'est ça qui dit "la TV X a accepté seulement
//  la stratégie 2 avec PN MPEG_TS_SD_NA_ISO" — info empirique
//  irremplaçable.
//
//  Aucune des classes n'a de comportement — uniquement des données
//  + sérialisation JSON.
// =========================================================

import 'package:flutter/foundation.dart';

import '../domain/cast_device.dart';
import 'dlna_profiles.dart';

@immutable
class ProbeSummary {
  const ProbeSummary({
    required this.success,
    required this.finalUrl,
    required this.redirectCount,
    required this.timeToFirstByteMs,
    this.mime,
    this.contentLength,
    this.acceptsRanges = false,
    this.requiresAuth = false,
    this.errorCode,
    this.errorReason,
  });

  final bool success;
  final String finalUrl;
  final int redirectCount;
  final int? timeToFirstByteMs;
  final String? mime;
  final int? contentLength;
  final bool acceptsRanges;
  final bool requiresAuth;
  final int? errorCode;
  final String? errorReason;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'success': success,
        'finalUrl': redactStreamUrl(finalUrl),
        'redirectCount': redirectCount,
        'timeToFirstByteMs': timeToFirstByteMs,
        if (mime != null) 'mime': mime,
        if (contentLength != null) 'contentLength': contentLength,
        'acceptsRanges': acceptsRanges,
        'requiresAuth': requiresAuth,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorReason != null) 'errorReason': redactCastText(errorReason!),
      };
}

@immutable
class SinkSummary {
  const SinkSummary({
    required this.entryCount,
    required this.mimeTypes,
    required this.profileNames,
  });

  final int entryCount;
  final List<String> mimeTypes;
  final List<String> profileNames;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entryCount': entryCount,
        'mimeTypes': mimeTypes,
        'profileNames': profileNames,
      };
}

@immutable
class ProfileSummary {
  const ProfileSummary({
    required this.mime,
    required this.transferMode,
    required this.objectClass,
    this.profileName,
  });

  final String mime;
  final String? profileName;
  final String transferMode;
  final String objectClass;

  factory ProfileSummary.from(DlnaProfile p) => ProfileSummary(
        mime: p.mime,
        profileName: p.profileName,
        transferMode: p.transferMode.header,
        objectClass: p.objectClass,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mime': mime,
        if (profileName != null) 'profileName': profileName,
        'transferMode': transferMode,
        'objectClass': objectClass,
      };
}

@immutable
class AttemptResult {
  const AttemptResult({
    required this.strategyIndex,
    required this.strategyName,
    required this.urlKind,
    required this.metadataMode,
    required this.durationMs,
    required this.success,
    this.errorMessage,
    this.lastCastUrlRedacted,
  });

  /// Index brut dans la ladder (0 = direct, 1 = relay+full, 2 = relay+min).
  final int strategyIndex;

  /// Libellé court pour l'UI : "direct+full", "relay+full", "relay+minimal".
  final String strategyName;

  /// "direct" ou "relay" — ce qui a été envoyé au récepteur.
  final String urlKind;

  /// "full" / "minimal" / "none" — mode de metadata employé.
  final String metadataMode;

  final int durationMs;
  final bool success;
  final String? errorMessage;

  /// URL exacte transmise a loadMedia pour cette tentative (token masque).
  /// Null si non applicable (ex: chemin DLNA ou echec avant loadMedia).
  final String? lastCastUrlRedacted;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'strategy': strategyName,
        'urlKind': urlKind,
        'metadataMode': metadataMode,
        'durationMs': durationMs,
        'success': success,
        if (errorMessage != null) 'errorMessage': redactCastText(errorMessage!),
        if (lastCastUrlRedacted != null)
          'lastCastUrlRedacted': lastCastUrlRedacted,
      };
}

/// Diagnostic complet d'UNE session castTo. Mutable pendant la
/// session (le CastManager l'enrichit au fil des étapes), figé
/// quand on l'archive dans le ring buffer.
class CastSessionDiagnostic {
  CastSessionDiagnostic({
    required this.startedAt,
    required this.device,
    required this.originalUrl,
    this.channelName,
    this.channelGenre,
  });

  final DateTime startedAt;
  final CastDevice device;
  final String? channelName;

  /// Libellé du genre (pas l'enum — on évite de coupler le module
  /// cast au module channels). Le caller passe `.genre.label` si dispo.
  final String? channelGenre;

  final String originalUrl;

  ProbeSummary? probe;
  SinkSummary? sink;
  ProfileSummary? profile;

  final List<AttemptResult> attempts = <AttemptResult>[];

  int? totalDurationMs;
  bool success = false;
  String? finalErrorMessage;
  String? finalUserMessage;

  /// Pré-vol réseau (2026-06-01) : résultat du test de joignabilité
  /// TCP de la TV avant de tenter le cast. `null` = pas testé (cas
  /// Chromecast), `true` = socket ouverte, `false` =
  /// injoignable (probable AP isolation / TV endormie / autre WiFi).
  bool? deviceReachable;

  /// Stratégie qui a finalement marché — `null` si tout a échoué.
  AttemptResult? get winningAttempt {
    for (final AttemptResult a in attempts) {
      if (a.success) return a;
    }
    return null;
  }

  /// `true` si on a une donnée probe + au moins une tentative.
  bool get isComplete => totalDurationMs != null;

  Map<String, dynamic> toJson() {
    final AttemptResult? win = winningAttempt;
    final ProbeSummary? p = probe;
    final SinkSummary? s = sink;
    final ProfileSummary? pr = profile;
    return <String, dynamic>{
      'startedAt': startedAt.toIso8601String(),
      'device': <String, dynamic>{
        'name': device.name,
        'kind': device.kind.name,
        'host': device.host,
        if (device.manufacturer != null) 'manufacturer': device.manufacturer,
        if (device.model != null) 'model': device.model,
      },
      if (channelName != null) 'channelName': channelName,
      if (channelGenre != null) 'channelGenre': channelGenre,
      'originalUrl': redactStreamUrl(originalUrl),
      if (p != null) 'probe': p.toJson(),
      if (s != null) 'sink': s.toJson(),
      if (pr != null) 'profile': pr.toJson(),
      'attempts':
          attempts.map((AttemptResult a) => a.toJson()).toList(growable: false),
      if (totalDurationMs != null) 'totalDurationMs': totalDurationMs,
      if (deviceReachable != null) 'deviceReachable': deviceReachable,
      'success': success,
      if (win != null) 'winningStrategy': win.strategyName,
      if (finalUserMessage != null)
        'finalUserMessage': redactCastText(finalUserMessage!),
      if (finalErrorMessage != null && kDebugMode)
        'finalErrorMessage': redactCastText(finalErrorMessage!),
    };
  }
}

/// Masque token/credentials dans une URL avant export public.
/// Utilisé par tous les `toJson()` du diagnostic. On ne veut PAS
/// qu'un testeur partage par mégarde son URL Xtream complète
/// (avec USER/PASS) dans une issue GitHub publique.
String redactStreamUrl(String url) {
  Uri u;
  try {
    u = Uri.parse(url);
  } on FormatException {
    return '<url invalide>';
  }
  // Les chemins nus /USER/PASS/ID.ts et /cs/<base64>.ts portent aussi
  // des secrets. Masquer seulement « password » dans query ne suffit pas.
  // Le rapport garde l'hôte, les routes connues et l'extension du média,
  // jamais les valeurs de query, fragments ou chemins d'abonnement.
  const publicRoutes = <String>{
    'live',
    'movie',
    'series',
    'hls',
    'relay',
    'cs',
    'cast-sign',
    'cast-proxy',
    'cast-receiver',
    'get.php',
    'player_api.php'
  };
  final List<String> segments = <String>[];
  for (int i = 0; i < u.pathSegments.length; i++) {
    final String segment = u.pathSegments[i];
    if (i == 0 && publicRoutes.contains(segment)) {
      segments.add(segment);
    } else {
      final Match? extension =
          RegExp(r'\.([A-Za-z0-9]{1,5})$').firstMatch(segment);
      segments.add(extension == null ? '***' : '***.${extension.group(1)}');
    }
  }
  return u
      .replace(
        userInfo: u.userInfo.isEmpty ? '' : '***',
        pathSegments: segments,
        fragment: '',
        queryParameters: u.queryParameters.isEmpty
            ? null
            : <String, String>{
                for (final key in u.queryParameters.keys) key: '***'
              },
      )
      .toString();
}

/// Les exceptions réseau contiennent souvent l'URL complète dans leur
/// texte, parfois percent-encodée. Le même filtre s'applique avant copie
/// du rapport et avant journalisation, y compris aux messages de secours.
String redactCastText(String text) {
  String safe = text;
  for (int i = 0; i < 2 && safe.contains('%'); i++) {
    try {
      final String decoded = Uri.decodeFull(safe);
      if (decoded == safe) break;
      safe = decoded;
    } on FormatException {
      break;
    }
  }
  safe = safe.replaceAllMapped(
      RegExp(r'\b(Bearer|Basic)\s+\S+', caseSensitive: false),
      (Match match) => '${match.group(1)} ***');
  safe = safe.replaceAllMapped(
    RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
    (Match match) => redactStreamUrl(match.group(0)!),
  );
  return safe.replaceAllMapped(
    RegExp(
        r'''["']?\b(password|passwd|pass|pwd|token|access_token|refresh_token|authorization|username|user|login|t)["']?\s*[:=]\s*["']?[^\s&;,"'}]+''',
        caseSensitive: false),
    (Match match) => '${match.group(1)}=***',
  );
}
