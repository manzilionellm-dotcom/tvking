// =========================================================
//  subscription_signature.dart — Vérification anti-piratage
// =========================================================
//  Rôle : vérifier que la réponse de licence reçue du serveur
//  (/api/heartbeat, /api/status/:mac) a bien été SIGNÉE par NOTRE
//  serveur, et non fabriquée par un faux serveur monté par un
//  pirate (redirection DNS, fichier hosts, APK repackagée pointant
//  vers une autre adresse…).
//
//  Modèle de sécurité (signature asymétrique Ed25519) :
//    • Le serveur détient la clé PRIVÉE (secret Cloudflare, jamais
//      exposée). Il signe chaque réponse de licence.
//    • L'app embarque seulement la clé PUBLIQUE ci-dessous. Elle ne
//      permet QUE de vérifier — l'extraire de l'APK ne donne aucun
//      moyen de forger une signature.
//    • Un faux serveur ne peut donc pas produire une réponse
//      « payé / débloqué » que l'app accepterait.
//
//  La signature couvre aussi la MAC demandée et un horodatage `ts`,
//  donc on ne peut pas non plus :
//    • rejouer la réponse « payée » d'un AUTRE appareil (mac liée),
//    • rejouer une vieille réponse indéfiniment (fraîcheur de `ts`).
//
//  ⚠️ DÉPLOIEMENT EN DEUX TEMPS (pour ne JAMAIS bloquer un client
//  légitime) :
//    1. Le Worker ne signe QUE si le secret LICENSE_SIGNING_KEY est
//       posé. Tant qu'il n'est pas posé, les réponses n'ont pas de
//       champ `sig`.
//    2. Côté app, l'exigence de signature est pilotée par le drapeau
//       [kRequireSignature]. Il reste à `false` tant que le secret
//       n'est pas en place côté serveur. Une fois le secret posé ET
//       vérifié (les réponses contiennent `sig`), on passe le drapeau
//       à `true` et on rebuild l'APK : à partir de là, toute réponse
//       non signée ou mal signée est ignorée (l'app retombe sur le
//       trial local, comme si le serveur était injoignable).
// =========================================================

import 'dart:convert';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/foundation.dart';

/// Drapeau d'exigence de signature.
///
/// `false` (défaut, sûr) : on VÉRIFIE la signature si elle est présente
/// — utile pour valider le déploiement — mais on n'EXIGE pas qu'elle le
/// soit. Aucun changement de comportement pour les clients existants.
///
/// `true` : une réponse qui débloque l'app (`paid` ou statut non bloqué)
/// DOIT porter une signature valide, fraîche et liée à la bonne MAC.
/// Sinon elle est rejetée → l'app retombe sur le trial local. À activer
/// SEULEMENT après avoir posé le secret côté Worker et confirmé que les
/// réponses contiennent bien `sig`.
const bool kRequireSignature = false;

/// Clé publique Ed25519 (base64 standard, 32 octets) correspondant à la
/// clé privée détenue par le Worker (secret LICENSE_SIGNING_KEY). Ce
/// n'est PAS un secret : elle ne sert qu'à vérifier.
const String _kLicensePublicKeyB64 =
    'u+oLAfakoh7GNoF/xWWgR28SEr5HyB42tjcOPIr8L/A=';

/// Tolérance de fraîcheur de l'horodatage signé. On accepte une réponse
/// signée jusqu'à 7 jours d'âge : ça couvre l'horloge mal réglée d'un
/// appareil et de courtes coupures, sans permettre de rejouer une
/// vieille réponse « payée » éternellement.
const Duration _kSignatureMaxAge = Duration(days: 7);

abstract final class SubscriptionSignature {
  /// `true` si [json] contient une signature de licence (`sig`).
  static bool isPresent(Map<String, dynamic> json) =>
      json['sig'] is String && (json['sig'] as String).isNotEmpty;

  /// Vérifie la signature Ed25519 de la réponse [json] pour la [mac]
  /// donnée. Renvoie `true` uniquement si la signature est présente,
  /// cryptographiquement valide, liée à cette MAC, et suffisamment
  /// fraîche.
  ///
  /// [nowMs] permet d'injecter l'horloge en test ; par défaut l'heure
  /// courante.
  static bool verify(String mac, Map<String, dynamic> json, {int? nowMs}) {
    try {
      final String? sigB64 = json['sig'] as String?;
      if (sigB64 == null || sigB64.isEmpty) return false;

      final int ts = (json['ts'] as num?)?.toInt() ?? 0;
      if (ts <= 0) return false;

      // Fraîcheur : pas trop vieux, et pas trop dans le futur (5 min de
      // marge pour les horloges légèrement en avance).
      final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (now - ts > _kSignatureMaxAge.inMilliseconds) return false;
      if (ts - now > const Duration(minutes: 5).inMilliseconds) return false;

      // Reconstruit la chaîne canonique EXACTEMENT comme le Worker
      // (mêmes champs, même ordre, mêmes séparateurs). La moindre
      // différence fait échouer la vérification.
      final String message = _canonical(mac, json, ts);

      final ed.PublicKey pub =
          ed.PublicKey(base64.decode(_kLicensePublicKeyB64));
      final List<int> sig = base64.decode(sigB64);

      return ed.verify(pub, Uint8List.fromList(utf8.encode(message)),
          Uint8List.fromList(sig));
    } catch (e) {
      if (kDebugMode) debugPrint('[Signature] verify error: $e');
      return false;
    }
  }

  /// Chaîne canonique signée — DOIT rester identique à
  /// `licenseCanonical()` côté Worker (cloudflare/worker.js).
  static String _canonical(String mac, Map<String, dynamic> json, int ts) {
    int b(Object? v) => v == true ? 1 : 0;
    int n(Object? v) => (v is num) ? v.toInt() : 0;
    return <Object>[
      'v1',
      mac,
      b(json['paid']),
      b(json['expired']),
      b(json['frozen']),
      b(json['banned']),
      n(json['days_left']),
      n(json['trial_until']),
      ts,
    ].join('|');
  }
}
