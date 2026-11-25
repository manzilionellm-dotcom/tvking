// Tarifs d'affichage pilotés par le panel. Aucun montant, paiement ou durée
// d'accès n'est inventé localement ; le statut de licence garde son propre
// serveur et ses règles. Le témoin `configured` distingue une configuration
// enregistrée des valeurs historiques par défaut d'un ancien Worker.
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
    this.confirmed = false,
    this.blockTitleFr = '',
    this.blockBodyFr = '',
    this.blockTitleEn = '',
    this.blockBodyEn = '',
    this.payUrl = '',
  });

  final String currency;
  final String lifetime;
  final String yearly;
  final int trialDays;
  final bool promoEnabled;
  final String promoMessage;
  final bool confirmed;
  final String blockTitleFr;
  final String blockBodyFr;
  final String blockTitleEn;
  final String blockBodyEn;
  final String payUrl;

  // « Inconnu » n'est jamais un tarif à facturer ni une promesse d'essai.
  static const PricingConfig fallback = PricingConfig(
    currency: '', lifetime: '', yearly: '', trialDays: 0,
    promoEnabled: false, promoMessage: '',
  );

  bool get hasOffers => confirmed && currency.isNotEmpty &&
      (lifetime.isNotEmpty || yearly.isNotEmpty);
  String get lifetimeLabel => '$lifetime $currency'.trim();
  String get yearlyLabel => '$yearly $currency'.trim();
  String blockTitle(String language) => language == 'fr' ? blockTitleFr : blockTitleEn;
  String blockBody(String language) => language == 'fr' ? blockBodyFr : blockBodyEn;

  static String _text(Object? value, int max) {
    if (value is! String) return '';
    final String clean = value.replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), '').trim();
    return clean.length > max ? clean.substring(0, max) : clean;
  }

  static String _price(Object? value) {
    final String price = _text(value, 30);
    return RegExp(r'^(?:0|[1-9]\d{0,6})(?:[.,]\d{1,2})?$').hasMatch(price) ? price : '';
  }

  static String _paymentUrl(Object? value) {
    final String raw = _text(value, 500);
    final Uri? uri = Uri.tryParse(raw);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
        uri.userInfo.isEmpty ? uri.toString() : '';
  }

  factory PricingConfig.fromJson(Map<dynamic, dynamic> json) {
    if (json['configured'] != true) return fallback;
    final String currency = _text(json['currency'], 8);
    final bool currencyOk = RegExp(r'^[A-Za-z€£$¥₹₩₺₽₫฿₱₦₪₴₡₲₵₸₭₮₼₾₿]{1,8}$').hasMatch(currency);
    final Object? trial = json['trialDays'];
    return PricingConfig(
      confirmed: true,
      currency: currencyOk ? currency : '',
      lifetime: _price(json['lifetime']),
      yearly: _price(json['yearly']),
      trialDays: trial is int && trial >= 0 && trial <= 365 ? trial : 0,
      promoEnabled: json['promoEnabled'] == true,
      promoMessage: _text(json['promoMessage'], 500),
      blockTitleFr: _text(json['blockTitleFr'], 120),
      blockBodyFr: _text(json['blockBodyFr'], 500),
      blockTitleEn: _text(json['blockTitleEn'], 120),
      blockBodyEn: _text(json['blockBodyEn'], 500),
      payUrl: _paymentUrl(json['payUrl']),
    );
  }
}

abstract final class PricingRepository {
  static final ValueNotifier<PricingConfig> notifier =
      ValueNotifier<PricingConfig>(PricingConfig.fallback);
  static PricingConfig get current => notifier.value;
  static Future<void>? _flight;
  static int _generation = 0;
  @visibleForTesting
  static http.Client? client;

  // Les lectures UI partagent une requête ; chaque ordre strict relit ensuite.
  // Le mode strict ne transforme jamais une panne en accusé « appliqué ».
  static Future<void> fetch({bool strict = false}) async {
    // Une lecture partie avant l'ordre peut encore contenir l'ancienne valeur.
    // Le strict attend sa fin, puis démarre sa propre lecture après l'ordre.
    // La boucle sérialise aussi plusieurs ordres stricts sans réponse tardive.
    if (strict) {
      while (_flight != null) {
        final previous = _flight!;
        try {
          await previous;
        } catch (_) {
          // Seule la nouvelle lecture décide du succès de cet ordre.
        }
        if (identical(_flight, previous)) _flight = null;
      }
    }
    final Future<void> flight = _flight ??= _read();
    try { await flight; }
    catch (error) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[Pricing] lecture indisponible');
    } finally {
      if (identical(_flight, flight)) _flight = null;
    }
  }

  static Future<void> _read() async {
    final int generation = _generation;
    final Uri uri = Uri.parse('$kSubscriptionBaseUrl/api/pricing');
    final http.Response response = await (client?.get(uri) ?? http.get(uri))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw StateError('pricing_http_error');
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['configured'] is! bool) {
      throw const FormatException('pricing_contract_unavailable');
    }
    final PricingConfig config = PricingConfig.fromJson(decoded);
    if (generation == _generation) notifier.value = config;
  }

  @visibleForTesting
  static void resetForTesting() {
    _generation++;
    _flight = null;
    client = null;
    notifier.value = PricingConfig.fallback;
  }
}
