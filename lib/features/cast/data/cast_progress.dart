// =========================================================
//  cast_progress.dart — Messages d'état pour l'UI
// =========================================================
//  Les utilisateurs ne doivent JAMAIS voir un "HTTP 500" ou un
//  "SOAPAction failed". Ce fichier traduit chaque étape interne
//  du failover en un message humain en français court (1 ligne)
//  qu'on affiche dans le picker / mini-bar / VideoPlayerScreen.
//
//  L'orchestrator pousse un `CastProgress` à chaque transition,
//  le CastManager l'expose en ChangeNotifier, et l'UI s'abonne.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../../core/i18n/app_l10n.dart';

/// Étapes ordonnées d'une session de cast — du plus optimiste au
/// plus dégradé. Toutes ne sont pas atteintes : si la 1ère réussit,
/// on saute directement à [streaming].
enum CastStage {
  /// Aucun cast en cours.
  idle,

  /// Pré-vol : on vérifie l'URL upstream avant de la pousser au
  /// récepteur. Évite 9 erreurs sur 10 (token expiré, 302 cascadé,
  /// MIME bizarre).
  validatingStream,

  /// On interroge le récepteur pour récupérer ses profils DLNA
  /// supportés (ConnectionManager:GetProtocolInfo).
  detectingReceiver,

  /// Mise en route du serveur HTTP local qui va servir de relay
  /// (réécriture des headers + DLNA-compatibility).
  startingRelay,

  /// Envoi SOAP SetAVTransportURI + Play vers le récepteur.
  connectingToReceiver,

  /// La 1ère tentative a échoué — on essaye un profil différent
  /// ou la route relay.
  retryingWithFallback,

  /// On bascule vers le navigateur web (QR code) car DLNA refuse
  /// toutes les variantes du flux.
  switchingToWebFallback,

  /// La lecture démarre côté récepteur. Idéalement < 3s après le tap.
  streaming,

  /// Cast en pause (déclenché par l'utilisateur).
  paused,

  /// Échec final — toutes les routes ont été tentées sans succès.
  failed,
}

@immutable
class CastProgress {
  const CastProgress({
    required this.stage,
    required this.message,
    this.attempt = 1,
    this.totalAttempts = 1,
    this.technicalDetail,
  });

  final CastStage stage;

  /// Message court en français, prêt à afficher (max ~60 caractères).
  final String message;

  /// Numéro de la tentative en cours (1-based). Permet à l'UI de
  /// montrer "2/5" sans devoir le calculer.
  final int attempt;
  final int totalAttempts;

  /// Détail technique uniquement utile en debug (panneau diagnostic
  /// dev). NE DOIT PAS être affiché à l'utilisateur final.
  final String? technicalDetail;

  CastProgress copyWith({
    CastStage? stage,
    String? message,
    int? attempt,
    int? totalAttempts,
    String? technicalDetail,
  }) {
    return CastProgress(
      stage: stage ?? this.stage,
      message: message ?? this.message,
      attempt: attempt ?? this.attempt,
      totalAttempts: totalAttempts ?? this.totalAttempts,
      technicalDetail: technicalDetail ?? this.technicalDetail,
    );
  }

  static const CastProgress idle =
      CastProgress(stage: CastStage.idle, message: '');

  // ---- Constructeurs préfaits (traduits dans la langue active) ----
  //  Getters (et non const) : le message est résolu au moment de
  //  l'émission via AppL10n — donc toujours dans la langue en cours.

  static CastProgress get validating => CastProgress(
        stage: CastStage.validatingStream,
        message: AppL10n.current.castStageValidating,
      );

  static CastProgress get detecting => CastProgress(
        stage: CastStage.detectingReceiver,
        message: AppL10n.current.castStageDetecting,
      );

  static CastProgress get relayStarting => CastProgress(
        stage: CastStage.startingRelay,
        message: AppL10n.current.castStageRelayStarting,
      );

  static CastProgress connecting({int attempt = 1, int total = 1}) {
    return CastProgress(
      stage: CastStage.connectingToReceiver,
      message: total > 1
          ? AppL10n.current.castStageConnectingAttempt(attempt, total)
          : AppL10n.current.castStageConnecting,
      attempt: attempt,
      totalAttempts: total,
    );
  }

  static CastProgress retrying({
    required int attempt,
    required int total,
    required String reason,
  }) {
    return CastProgress(
      stage: CastStage.retryingWithFallback,
      message: AppL10n.current.castStageRetrying(attempt, total),
      attempt: attempt,
      totalAttempts: total,
      technicalDetail: reason,
    );
  }

  static CastProgress get webFallback => CastProgress(
        stage: CastStage.switchingToWebFallback,
        message: AppL10n.current.castStageWebFallback,
      );

  static CastProgress get live => CastProgress(
        stage: CastStage.streaming,
        message: AppL10n.current.castStageLive,
      );

  static CastProgress get pausedState => CastProgress(
        stage: CastStage.paused,
        message: AppL10n.current.castStagePaused,
      );

  static CastProgress failure(String userMessage, {String? details}) {
    return CastProgress(
      stage: CastStage.failed,
      message: userMessage,
      technicalDetail: details,
    );
  }
}
