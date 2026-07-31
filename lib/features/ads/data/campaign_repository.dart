// =========================================================
//  campaign_repository.dart — Affiliation & bannières cliquables
// =========================================================
//  Campagnes posées par le panel (« Affiliation & Pubs ») et affichées
//  en CARTE DISCRÈTE sur l'accueil (cf. AffiliateCard). Côté serveur :
//    - GET  /api/campaigns        (public) → campagnes actives
//    - POST /api/campaigns/track  (public) → +1 impression ou clic
//  Ciblage horaire évalué ICI sur l'heure LOCALE du client
//  (start_hour/end_hour, fenêtre qui peut passer minuit : 22 → 2).
//  Rotation : s'il y a plusieurs campagnes éligibles, on en montre UNE
//  seule, qui change chaque jour — jamais un mur de pubs.
//  Best-effort partout : réseau KO = pas de carte, jamais d'erreur.
//  Aucune dépendance au cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart';

/// Une campagne telle que renvoyée par le Worker. Immuable.
@immutable
class Campaign {
  const Campaign({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.targetUrl,
    required this.cta,
    required this.placement,
    required this.startHour,
    required this.endHour,
  });

  final int id;

  /// `banner` (image + titre) ou `product` (carte « Acheter »).
  final String kind;
  final String title;
  final String body;
  final String imageUrl;

  /// Lien d'affiliation — ouvert nativement (Intent.ACTION_VIEW).
  final String targetUrl;

  /// Libellé du bouton (ex. « Acheter »). Vide → libellé générique.
  final String cta;
  final String placement;

  /// Fenêtre horaire optionnelle (0-23, heure LOCALE). null = toujours.
  final int? startHour;
  final int? endHour;

  static Campaign? fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    final int id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    final String targetUrl = (json['target_url'] ?? '').toString();
    // Sans id ou sans lien il n'y a rien à montrer ni à compter.
    if (id <= 0 || targetUrl.isEmpty) return null;
    int? hour(Object? v) {
      if (v == null) return null;
      final int? n = v is int ? v : int.tryParse('$v');
      return (n != null && n >= 0 && n <= 23) ? n : null;
    }

    return Campaign(
      id: id,
      kind: (json['kind'] ?? 'banner').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      targetUrl: targetUrl,
      cta: (json['cta'] ?? '').toString(),
      placement: (json['placement'] ?? 'home').toString(),
      startHour: hour(json['start_hour']),
      endHour: hour(json['end_hour']),
    );
  }

  /// `true` si la campagne est diffusable à l'heure [hour] (locale).
  /// Fenêtre inclusive ; si elle enjambe minuit (22 → 2) on accepte
  /// hour >= start OU hour <= end.
  bool visibleAtHour(int hour) {
    final int? from = startHour;
    final int? to = endHour;
    if (from == null && to == null) return true;
    final int f = from ?? 0;
    final int t = to ?? 23;
    return f <= t ? (hour >= f && hour <= t) : (hour >= f || hour <= t);
  }
}

abstract final class CampaignRepository {
  /// Clé SharedPreferences : ids fermés par l'utilisateur (bornés).
  static const String _kDismissedKey = 'campaigns.dismissed_ids';
  static const int _kDismissedMax = 50;

  /// Signal « les campagnes ont (peut-être) changé » — incrémenté par le
  /// temps réel (RealtimeSyncService, évènement `sync config`) quand
  /// l'owner crée/modifie une campagne. La carte l'écoute et re-fetch.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() => revision.value++;

  /// Impressions déjà comptées CETTE session (une par campagne par
  /// session — pas une par rebuild du widget).
  static final Set<int> _impressed = <int>{};

  /// Récupère les campagnes actives. `[]` si aucune / erreur réseau.
  static Future<List<Campaign>> fetchAll() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/campaigns'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return const <Campaign>[];
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return const <Campaign>[];
      final Object? list = decoded['campaigns'];
      if (list is! List) return const <Campaign>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Campaign.fromJson)
          .whereType<Campaign>()
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[Campaigns] fetch: $e');
      return const <Campaign>[];
    }
  }

  /// Choisit LA campagne à montrer sur l'accueil : placement `home`,
  /// fenêtre horaire respectée, pas fermée par l'utilisateur. S'il en
  /// reste plusieurs, rotation quotidienne (jour de l'année modulo n) —
  /// une seule carte à la fois, qui change chaque jour.
  static Campaign? pickForHome(
    List<Campaign> all, {
    required Set<int> dismissed,
    DateTime? now,
  }) {
    final DateTime n = now ?? DateTime.now();
    final List<Campaign> eligible = all
        .where((Campaign c) =>
            c.placement == 'home' &&
            c.visibleAtHour(n.hour) &&
            !dismissed.contains(c.id))
        .toList(growable: false);
    if (eligible.isEmpty) return null;
    final int dayOfYear =
        n.difference(DateTime(n.year)).inDays; // 0-based
    return eligible[dayOfYear % eligible.length];
  }

  /// Ids fermés par l'utilisateur (persistés).
  static Future<Set<int>> dismissedIds() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_kDismissedKey) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  /// Mémorise la fermeture de [id] (liste bornée : on garde les plus
  /// récents, les vieux ids correspondent à des campagnes disparues).
  static Future<void> dismiss(int id) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> ids =
          prefs.getStringList(_kDismissedKey) ?? <String>[];
      ids.remove('$id');
      ids.add('$id');
      while (ids.length > _kDismissedMax) {
        ids.removeAt(0);
      }
      await prefs.setStringList(_kDismissedKey, ids);
    } catch (_) {
      // best-effort
    }
  }

  /// +1 impression (une seule fois par campagne et par session).
  static void trackImpression(int id) {
    if (!_impressed.add(id)) return;
    _track(id, 'impression');
  }

  /// +1 clic.
  static void trackClick(int id) => _track(id, 'click');

  static void _track(int id, String event) {
    // Fire-and-forget : un comptage raté ne doit rien bloquer.
    http
        .post(
          Uri.parse('$kSubscriptionBaseUrl/api/campaigns/track'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, Object>{'id': id, 'event': event}),
        )
        .timeout(const Duration(seconds: 6))
        .then((_) {}, onError: (Object e) {
      if (kDebugMode) debugPrint('[Campaigns] track: $e');
    });
  }
}
