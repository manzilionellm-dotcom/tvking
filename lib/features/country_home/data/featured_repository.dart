// =========================================================
//  featured_repository.dart — "Favori du jour" (piloté panel)
// =========================================================
//  L'admin met une chaîne en avant chaque jour (ex. TF1 + « Mondial
// aujourd'hui »). L'app la lit ici et l'affiche dans son grand HERO
//  d'accueil à la place du #1 automatique — pour que l'app vive au
//  quotidien. Vide = HERO normal.
//
//  Cache local (lecture immédiate au boot) + rafraîchissement réseau.
//  ChangeNotifier → l'accueil se met à jour tout seul. Zéro cast.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart';

class FeaturedRepository extends ChangeNotifier {
  FeaturedRepository._();
  static final FeaturedRepository instance = FeaturedRepository._();

  String _name = '';
  String _note = '';
  bool _initialized = false;

  /// Nom de la chaîne mise en avant ('' = aucune).
  String get name => _name;

  /// Note associée (ex. « Mondial aujourd'hui »).
  String get note => _note;

  bool get hasFeatured => _name.trim().isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/featured'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;
      final String name = (decoded['name'] ?? '').toString();
      final String note = (decoded['note'] ?? '').toString();
      if (name != _name || note != _note) {
        _name = name;
        _note = note;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Featured] $e');
    }
  }
}
