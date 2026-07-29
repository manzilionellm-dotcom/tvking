// =========================================================
//  profiles_repository.dart — Profils famille (façon Netflix)
// =========================================================
//  Chaque membre de la famille a SON profil : ses « Derniers vus » (films),
//  son historique de recherche et ses collections de favoris. Les données
//  par profil sont obtenues en SUFFIXANT les clés de stockage locales
//  (SharedPreferences) : le profil « Famille » (par défaut) garde les clés
//  HISTORIQUES sans suffixe → zéro migration, zéro perte de données.
//
//  STABILITÉ : aucune interaction avec le lecteur vidéo ni l'écran Direct.
//  Les favoris (SQLite) restent PARTAGÉS par toute la famille — seul le
//  « petit confort » (récents/recherches/collections) est par profil.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../observability/structured_logger.dart';

/// Un profil : identifiant stable + nom + emoji d'avatar.
class TvProfile {
  const TvProfile({required this.id, required this.name, required this.emoji});

  final String id;
  final String name;
  final String emoji;
}

class ProfilesRepository extends ChangeNotifier {
  ProfilesRepository._();
  static final ProfilesRepository instance = ProfilesRepository._();

  static const String _kList = 'tv_profiles';
  static const String _kActive = 'tv_profile_active';
  static const int maxProfiles = 6;

  /// Le profil par défaut : conserve les clés historiques (pas de suffixe).
  static const TvProfile familyProfile =
      TvProfile(id: 'default', name: 'Famille', emoji: '🏠');

  List<TvProfile> _extras = <TvProfile>[];
  String _activeId = familyProfile.id;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Tous les profils : « Famille » d'abord, puis ceux créés.
  List<TvProfile> get profiles =>
      <TvProfile>[familyProfile, ..._extras];

  TvProfile get active => profiles.firstWhere(
        (TvProfile p) => p.id == _activeId,
        orElse: () => familyProfile,
      );

  /// Suffixe à AJOUTER aux clés SharedPreferences des données par profil.
  /// Vide pour « Famille » (compatibilité avec les données existantes).
  String get keySuffix =>
      _activeId == familyProfile.id ? '' : '.$_activeId';

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_kList) ?? '[]';
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _extras = list
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> j) => TvProfile(
                id: (j['id'] as String?) ?? '',
                name: (j['name'] as String?) ?? '',
                emoji: (j['emoji'] as String?) ?? '👤',
              ))
          .where((TvProfile p) => p.id.isNotEmpty && p.name.isNotEmpty)
          .toList(growable: true);
      _activeId = prefs.getString(_kActive) ?? familyProfile.id;
    } catch (e) {
      debugPrint('[Profils] load: $e');
      _extras = <TvProfile>[];
      _activeId = familyProfile.id;
    }
    _loaded = true;
    notifyListeners();
  }

  TvProfile? byName(String name) {
    for (final TvProfile p in profiles) {
      if (p.name == name) return p;
    }
    return null;
  }

  Future<void> create(String name, String emoji) async {
    final String n = name.trim();
    if (n.isEmpty || byName(n) != null) return;
    if (profiles.length >= maxProfiles) return;
    // Id stable dérivé du nom (pas d'horloge/aléa nécessaires ici).
    final String id =
        'p_${n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    if (profiles.any((TvProfile p) => p.id == id)) return;
    _extras.add(TvProfile(id: id, name: n, emoji: emoji));
    await _save();
  }

  Future<void> delete(String id) async {
    if (id == familyProfile.id) return; // « Famille » est indestructible
    _extras.removeWhere((TvProfile p) => p.id == id);
    if (_activeId == id) _activeId = familyProfile.id;
    await _save();
  }

  Future<void> setActive(String id) async {
    if (profiles.every((TvProfile p) => p.id != id)) return;
    _activeId = id;
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kList,
        jsonEncode(_extras
            .map((TvProfile p) => <String, Object?>{
                  'id': p.id,
                  'name': p.name,
                  'emoji': p.emoji,
                })
            .toList(growable: false)),
      );
      await prefs.setString(_kActive, _activeId);
    } catch (e) {
      debugPrint('[Profils] save: $e');
      // Perte de données silencieuse : les profils créés/renommés
      // disparaîtraient au prochain boot sans explication → on trace.
      StructuredLogger.instance.warn(
        domain: 'profiles',
        event: 'save_fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
    }
  }
}
