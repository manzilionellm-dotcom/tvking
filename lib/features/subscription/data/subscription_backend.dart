// =========================================================
//  subscription_backend.dart — Client backend côté souscription
// =========================================================
//  Pendant Dart du couple :
//
//    POST /api/heartbeat            (app → worker)
//    GET  /api/status/:mac          (app → worker)
//
//  Ces routes sont PUBLIQUES (pas d'auth admin) : l'identifiant
//  est le MAC virtuel du device, comme pour /config/:mac.
//
//  Le serveur retourne {status, paid, days_left, expired, frozen,
//  banned, trial_until}. L'app utilise ces champs pour afficher
//  un écran de blocage si le client ne doit plus pouvoir utiliser
//  l'app (gelé par l'admin, banni, ou essai expiré sans paiement).
//
//  Fallback hors-ligne : si le serveur est inaccessible, l'app
//  retombe sur le trial local 10 j de SubscriptionState. Ça
//  évite de bloquer un user légitime quand son WiFi a un creux.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/app/app_platform.dart';
import '../../../core/app/build_info.dart';
import '../../device/data/device_identity.dart';
import 'now_playing.dart';

/// URL du Worker Cloudflare — DOIT être le MÊME backend que celui
/// utilisé par le panneau admin (admin-panel, `VITE_API_BASE`), sinon
/// l'app lit un autre serveur que celui où le panel écrit les
/// activations/sources → « l'app ne se connecte pas avec le panel ».
///
/// Historique du bug : l'app a pointé sur `99999.7themotion.com` (ancien
/// worker) PUIS sur `seven-motion-backend.manzilionel-lm.workers.dev`
/// (sous-domaine workers.dev INJOIGNABLE → l'activation du panel ne
/// descendait jamais dans l'app). On aligne désormais sur le Custom
/// Domain FIABLE `app.7themotion.com` (= le worker que le panel utilise
/// aussi). Résultat : l'activation panel → app redevient automatique.
const String kSubscriptionBaseUrl =
    'https://app.7themotion.com';

/// Snapshot de l'état renvoyé par le serveur. Immuable.
@immutable
class RemoteSubscriptionStatus {
  const RemoteSubscriptionStatus({
    required this.exists,
    required this.status,
    required this.paid,
    required this.plan,
    required this.paidUntil,
    required this.daysLeft,
    required this.expired,
    required this.frozen,
    required this.banned,
    required this.trialUntil,
  });

  /// `true` si le serveur connaît ce MAC (= il a déjà fait un
  /// heartbeat). `false` la 1ère fois (création en cours).
  final bool exists;

  /// `'active'` | `'frozen'` | `'banned'` | `'unknown'`
  final String status;

  /// Abonnement payant valide.
  final bool paid;

  /// Type d'abonnement pour l'affichage :
  /// `'lifetime'` (à vie) | `'paid'`/`'1y'`/`'custom'` (durée limitée) |
  /// `'trial'` | `'expired'` | `'frozen'` | `'banned'` | `'unknown'`.
  final String plan;

  /// Fin de l'abonnement payant (ms epoch). `0` = aucune date connue
  /// (essai, ou abonnement à vie → voir `plan == 'lifetime'`).
  final int paidUntil;

  /// `true` si l'abonnement est à vie.
  bool get isLifetime => plan == 'lifetime';

  /// Jours d'essai restants (0 si épuisé ou inconnu).
  final int daysLeft;

  /// Essai épuisé ET non payé.
  final bool expired;

  /// Compte gelé par l'admin.
  final bool frozen;

  /// Compte banni par l'admin.
  final bool banned;

  /// Timestamp (ms epoch) d'expiration de l'essai.
  final int trialUntil;

  /// True si le client a le droit d'utiliser l'app.
  bool get canUse => !banned && !frozen && (paid || !expired);

  /// True si on doit afficher un écran bloquant.
  bool get shouldBlock => banned || frozen || (expired && !paid);

  factory RemoteSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return RemoteSubscriptionStatus(
      exists: json['exists'] == true,
      status: (json['status'] as String?) ?? 'unknown',
      paid: json['paid'] == true,
      plan: (json['plan'] as String?) ?? 'unknown',
      paidUntil: (json['paid_until'] as num?)?.toInt() ?? 0,
      daysLeft: (json['days_left'] as num?)?.toInt() ?? 0,
      expired: json['expired'] == true,
      frozen: json['frozen'] == true,
      banned: json['banned'] == true,
      trialUntil: (json['trial_until'] as num?)?.toInt() ?? 0,
    );
  }

  /// État vide utilisé quand le serveur est inaccessible — l'app
  /// retombera sur le trial local pour la durée de l'incident.
  static const RemoteSubscriptionStatus unknown = RemoteSubscriptionStatus(
    exists: false,
    status: 'unknown',
    paid: false,
    plan: 'unknown',
    paidUntil: 0,
    daysLeft: 0,
    expired: false,
    frozen: false,
    banned: false,
    trialUntil: 0,
  );
}

abstract final class SubscriptionBackend {
  /// Pingue le serveur : il crée la fiche du MAC s'il ne la connaît
  /// pas (trial 10 j auto), ou rafraîchit son `last_seen_at` sinon.
  /// Renvoie le statut courant. Timeout court (8 s) — pas question
  /// que l'app traîne au boot si le réseau est nase.
  static Future<RemoteSubscriptionStatus> heartbeat(String mac) async {
    try {
      // Infos appareil → le panel recense chaque Android où l'app tourne
      // (même partagée via WhatsApp), avec son modèle + numéro de build.
      final Map<String, String> info =
          await DeviceIdentity.instance.deviceInfo();
      final Map<String, Object?> payload = <String, Object?>{
        'mac': mac,
        'model': info['model'] ?? '',
        'manufacturer': info['manufacturer'] ?? '',
        'android': info['release'] ?? '',
        'sdk': info['sdk'] ?? '',
        'build': info['build'] ?? '',
        'appBuild': kBuildTs,
        // Chaîne en cours de visionnage (vide si rien) → panel « En ligne ».
        'channel': NowPlaying.instance.current,
        // 📱 mobile / 📺 tv → le panel distingue les deux apps.
        'platform': AppPlatform.id,
      };
      final http.Response resp = await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/heartbeat'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[Subscription] heartbeat HTTP ${resp.statusCode}');
        }
        return RemoteSubscriptionStatus.unknown;
      }
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      return RemoteSubscriptionStatus.fromJson(body);
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] heartbeat error: $e');
      return RemoteSubscriptionStatus.unknown;
    }
  }

  /// Lit l'état courant du serveur sans toucher au `last_seen_at`.
  /// Utilisé par le `SubscriptionCard` pour rafraîchir l'UI sans
  /// déclencher un nouveau heartbeat (eg. après un pull-to-refresh).
  static Future<RemoteSubscriptionStatus> getStatus(String mac) async {
    try {
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/status/$mac'),
            headers: const <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return RemoteSubscriptionStatus.unknown;
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      return RemoteSubscriptionStatus.fromJson(body);
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] getStatus error: $e');
      return RemoteSubscriptionStatus.unknown;
    }
  }
}
