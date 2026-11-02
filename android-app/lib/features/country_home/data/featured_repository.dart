// =========================================================
//  featured_repository.dart — "Favori du jour" (piloté panel)
// =========================================================
//  L'admin met une chaîne en avant chaque jour (ex. TF1 + « Mondial
//  aujourd'hui ⚽ »). L'app la lit ici et l'affiche dans son grand HERO
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
  Future<void>? _pending;

  /// Nom de la chaîne mise en avant ('' = aucune).
  String get name => _name;

  /// Note associée (ex. « Mondial aujourd'hui ⚽ »).
  String get note => _note;

  bool get hasFeatured => _name.trim().isNotEmpty;

  Future<void> initialize({bool strict = false}) async {
    if (_initialized && !strict) return;
    _initialized = true;
    if (strict) {
      await refresh(strict: true);
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh({bool strict = false}) async {
    try {
      final Future<void> pending = _pending ??= _fetchAndApply();
      try {
        await pending;
      } finally {
        if (identical(_pending, pending)) _pending = null;
      }
    } catch (e) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[Featured] ${e.runtimeType}');
    }
  }

  Future<void> _fetchAndApply() async {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/featured'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        throw StateError('Favori distant non confirmé');
      }
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['name'] is! String || decoded['note'] is! String) {
        throw const FormatException('Favori distant invalide');
      }
      final String name = decoded['name'] as String;
      final String note = decoded['note'] as String;
      if (name != _name || note != _note) {
        _name = name;
        _note = note;
        notifyListeners();
      }
  }
}
