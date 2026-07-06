// =========================================================
//  place_repository.dart — Ville choisie pour la météo (TV)
// =========================================================
//  Sur une TV il n'y a PAS de GPS : la météo était déduite de
//  l'adresse IP (nœud opérateur → souvent une ville voisine, ex.
//  « Kista » au lieu de la vraie ville). Ici on laisse l'utilisateur
//  CHOISIR sa ville UNE FOIS ; on la mémorise (SharedPreferences) et
//  la météo est ensuite calculée sur les coordonnées EXACTES de cette
//  ville. Tant que rien n'est choisi, on garde la détection auto (IP).
//
//  Géocodage + prévisions : Open-Meteo (gratuit, sans clé API, mêmes
//  codes météo WMO que l'app utilise déjà).
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Une ville choisie (nom exact + coordonnées).
@immutable
class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'country': country,
        'lat': latitude,
        'lon': longitude,
      };

  static SavedPlace? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? lat = o['lat'];
    final Object? lon = o['lon'];
    if (lat is! num || lon is! num) return null;
    final String name = (o['name'] ?? '').toString();
    if (name.isEmpty) return null;
    return SavedPlace(
      name: name,
      country: (o['country'] ?? '').toString(),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
  }

  /// Ce qu'on affiche dans la liste : « Tierp, Suède ».
  String get label => country.isEmpty ? name : '$name, $country';
}

class PlaceRepository extends ChangeNotifier {
  PlaceRepository._();
  static final PlaceRepository instance = PlaceRepository._();

  static const String _kKey = 'weather.place.v1';

  SavedPlace? _place; // null = détection automatique (IP)
  SavedPlace? get current => _place;

  /// True si l'utilisateur a explicitement fixé une ville.
  bool get isManual => _place != null;

  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        _place = SavedPlace.fromJson(jsonDecode(raw));
      }
    } catch (_) {
      // best-effort : pas de ville mémorisée => auto.
    }
    notifyListeners();
  }

  /// Fixe la ville choisie (ou `null` pour revenir à l'automatique).
  Future<void> setPlace(SavedPlace? place) async {
    _place = place;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (place == null) {
        await prefs.remove(_kKey);
      } else {
        await prefs.setString(_kKey, jsonEncode(place.toJson()));
      }
    } catch (_) {
      // best-effort : le choix reste au moins en mémoire pour la session.
    }
    notifyListeners();
  }

  /// Recherche de villes par nom via le géocodage Open-Meteo.
  /// `language` sert à obtenir les noms localisés (ex. « Suède »/« Sweden »).
  /// Best-effort : renvoie une liste vide en cas d'échec réseau.
  Future<List<SavedPlace>> search(String query, {String language = 'en'}) async {
    final String q = query.trim();
    if (q.length < 2) return const <SavedPlace>[];
    try {
      final Uri uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeQueryComponent(q)}'
        '&count=8&language=$language&format=json',
      );
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const <SavedPlace>[];
      final Object? j = jsonDecode(resp.body);
      if (j is! Map) return const <SavedPlace>[];
      final Object? results = j['results'];
      if (results is! List) return const <SavedPlace>[];
      final List<SavedPlace> out = <SavedPlace>[];
      for (final Object? r in results) {
        if (r is! Map) continue;
        final Object? lat = r['latitude'];
        final Object? lon = r['longitude'];
        final String name = (r['name'] ?? '').toString();
        if (lat is! num || lon is! num || name.isEmpty) continue;
        // On enrichit le nom avec la région/pays pour lever l'ambiguïté
        // (ex. plusieurs « Paris » dans le monde).
        final String admin = (r['admin1'] ?? '').toString();
        final String country = (r['country'] ?? '').toString();
        final String display =
            (admin.isNotEmpty && admin != name) ? '$name ($admin)' : name;
        out.add(SavedPlace(
          name: display,
          country: country,
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
        ));
      }
      return out;
    } catch (_) {
      return const <SavedPlace>[];
    }
  }
}
