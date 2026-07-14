// =========================================================
//  pricing_repository.dart — Tarifs pilotés par le panel
// =========================================================
//  Récupère les tarifs distants (`GET /api/pricing`) posés par le panel
//  « Tarifs » et les expose à l'UI via un ValueNotifier réactif :
//    - prix à vie / 1 an (chaînes en €, ex. "9,9")
//    - durée de l'essai gratuit (jours)
//    - message promo/bonus optionnel (ex. « 1 acheté = 1 offert »).
//
//  Best-effort : si le réseau échoue ou que rien n'est configuré, on
//  garde les valeurs maison par défaut (à vie 9,9 € · 1 an 4,9 € · essai
//  7 jours). Aucune URL de flux ici (règle AGENTS n°2). Aucun lien au cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

@immutable
class PricingConfig {
  const PricingConfig({
    required this.currency,
    required this.lifetime,
    required this.yearly,
    required this.trialDays,
    required this.promoEnabled,
    required this.promoMessage,
  });

  /// Symbole monétaire (par défaut « € »).
  final String currency;

  /// Prix « à vie » sous forme de chaîne d'affichage (ex. "9,9").
  final String lifetime;

  /// Prix « 1 an » sous forme de chaîne d'affichage (ex. "4,9").
  final String yearly;

  /// Durée de l'essai gratuit, en jours.
  final int trialDays;

  /// Le message promo/bonus est-il actif ?
  final bool promoEnabled;

  /// Message promo/bonus (ex. « 1 acheté = 1 offert pour ta famille »).
  final String promoMessage;

  /// Valeurs maison par défaut (réseau coupé / rien posé au panel).
  static const PricingConfig fallback = PricingConfig(
    currency: '€',
    lifetime: '35',
    yearly: '9,90',
    trialDays: 5,
    promoEnabled: false,
    promoMessage: '',
  );

  /// « 9,9 € » — prix à vie prêt à afficher.
  String get lifetimeLabel => '$lifetime $currency';

  /// « 4,9 € » — prix 1 an prêt à afficher.
  String get yearlyLabel => '$yearly $currency';
}

abstract final class PricingRepository {
  /// Source de vérité réactive : l'UI écoute ce notifier pour se mettre
  /// à jour dès que les tarifs distants arrivent.
  static final ValueNotifier<PricingConfig> notifier =
      ValueNotifier<PricingConfig>(PricingConfig.fallback);

  static PricingConfig get current => notifier.value;

  /// Récupère les tarifs distants et met à jour [notifier]. Best-effort.
  static Future<void> fetch() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/pricing'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;

      String str(String key, String fallback) {
        final String v = (decoded[key] ?? '').toString().trim();
        return v.isEmpty ? fallback : v;
      }

      final Object? td = decoded['trialDays'];
      final int trialDays =
          td is int ? td : int.tryParse('$td') ?? PricingConfig.fallback.trialDays;

      notifier.value = PricingConfig(
        currency: str('currency', '€'),
        lifetime: str('lifetime', '9,9'),
        yearly: str('yearly', '4,9'),
        trialDays: trialDays < 0 ? 7 : trialDays,
        promoEnabled: decoded['promoEnabled'] == true,
        promoMessage: (decoded['promoMessage'] ?? '').toString(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Pricing] $e');
    }
  }
}
