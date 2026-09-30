// =========================================================
//  family_profile_store.dart — Qui regarde, et ses listes
// =========================================================
//  « Maison » continue d'utiliser les favoris SQLite, l'historique
//  des chaînes et la reprise cinéma déjà en place.
//  Un autre profil écrit dans SharedPreferences, à part.
//  Si la lecture du disque échoue, on reste sur Maison.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../box_extras/box_flag.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../cinema/data/watch_progress.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../security/data/parental_controls.dart';
import '../domain/family_profile.dart';

class FamilyProfileStore extends ChangeNotifier {
  FamilyProfileStore._();
  static final FamilyProfileStore instance = FamilyProfileStore._();

  static final BoxFlag flag = BoxFlag('zuno.flag.family');

  static const String _kProfiles = 'zuno.family.profiles';
  static const String _kActive = 'zuno.family.active';
  static const String _kKidsBefore = 'zuno.family.kids_before';

  List<FamilyProfile> profiles = const <FamilyProfile>[kHomeProfile];
  String activeId = FamilyProfile.homeId;
  bool _kidsBefore = false;
  bool _ready = false;

  FamilyProfile get active {
    for (final FamilyProfile profile in profiles) {
      if (profile.id == activeId) return profile;
    }
    return kHomeProfile;
  }

  bool get isHome => active.isHome;

  Future<void> load() async {
    await flag.load();
    if (_ready) return;
    FavoritesRepository.instance.onScopeChanged = _saveFavorites;
    RecentlyWatchedRepository.instance.onScopeChanged = _saveRecent;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      profiles = decodeProfiles(prefs.getString(_kProfiles));
      final String? saved = prefs.getString(_kActive);
      activeId = profiles.any((FamilyProfile p) => p.id == saved)
          ? saved!
          : FamilyProfile.homeId;
      _kidsBefore = prefs.getBool(_kKidsBefore) ?? false;
    } catch (_) {
      profiles = const <FamilyProfile>[kHomeProfile];
      activeId = FamilyProfile.homeId;
    }
    _ready = true;
  }

  /// Branche les dépôts sur le profil actif. Interrupteur coupé :
  /// on revient à Maison, sans forcer le mode enfants.
  Future<void> apply() async {
    await load();
    if (!flag.value || isHome) {
      await FavoritesRepository.instance.bindHome();
      await RecentlyWatchedRepository.instance.bindHome();
      await WatchProgressRepository.instance.useProfile(null);
      notifyListeners();
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await FavoritesRepository.instance.bindProfile(
      activeId,
      (prefs.getStringList(_favKey(activeId)) ?? const <String>[]).toSet(),
    );
    await RecentlyWatchedRepository.instance.bindProfile(
      activeId,
      prefs.getStringList(_recentKey(activeId)) ?? const <String>[],
    );
    await WatchProgressRepository.instance.useProfile(activeId);
    if (active.child) {
      await ParentalControls.instance.setKidsMode(true);
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await flag.set(value);
    if (!value && active.child) {
      await ParentalControls.instance.setKidsMode(_kidsBefore);
    }
    await apply();
  }

  Future<FamilyProfile?> add({required String name, required bool child}) async {
    await load();
    if (profiles.length >= 6) return null;
    final FamilyProfile created = FamilyProfile(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? (child ? 'Enfant' : 'Adulte') : name.trim(),
      child: child,
    );
    profiles = <FamilyProfile>[...profiles, created];
    await _persistProfiles();
    notifyListeners();
    return created;
  }

  Future<void> removeActive() async {
    if (isHome) return;
    final String gone = activeId;
    if (active.child) {
      await ParentalControls.instance.setKidsMode(_kidsBefore);
    }
    profiles = profiles.where((FamilyProfile p) => p.id != gone).toList();
    activeId = FamilyProfile.homeId;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_favKey(gone));
      await prefs.remove(_recentKey(gone));
    } catch (_) {}
    await _persistProfiles();
    await apply();
  }

  /// Change de profil. Le code parental, s'il faut le demander,
  /// est vérifié par l'écran AVANT cet appel.
  Future<void> switchTo(String id) async {
    await load();
    if (!profiles.any((FamilyProfile p) => p.id == id)) return;
    if (id == activeId) return;
    final FamilyProfile next =
        profiles.firstWhere((FamilyProfile p) => p.id == id);
    final FamilyProfile previous = active;
    if (next.child && !previous.child) {
      _kidsBefore = ParentalControls.instance.kidsMode.value;
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kKidsBefore, _kidsBefore);
      } catch (_) {}
      await ParentalControls.instance.setKidsMode(true);
    } else if (previous.child && !next.child) {
      await ParentalControls.instance.setKidsMode(_kidsBefore);
    }
    activeId = id;
    await _persistProfiles();
    await apply();
  }

  Future<void> _persistProfiles() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProfiles, encodeProfiles(profiles));
      await prefs.setString(_kActive, activeId);
    } catch (_) {}
  }

  Future<void> _saveFavorites(String profileId, Set<String> ids) async {
    if (profileId == FamilyProfile.homeId) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favKey(profileId), ids.toList());
    } catch (_) {}
  }

  Future<void> _saveRecent(String profileId, List<String> ids) async {
    if (profileId == FamilyProfile.homeId) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey(profileId), ids);
    } catch (_) {}
  }

  static String _favKey(String id) => 'zuno.family.fav.$id';
  static String _recentKey(String id) => 'zuno.family.recent.$id';
}
