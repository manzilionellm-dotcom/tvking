import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/novatube_private_features.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import 'app_pin_settings.dart';
import 'parental_controls.dart';

/// Activation persistante par profil ; déverrouillage limité à une visite.
/// Aucun code, contenu ou compte n'est fourni par l'application.
class AdultAccess {
  AdultAccess._({required this.supported});
  static final AdultAccess instance = AdultAccess._(
    supported: NovatubePrivateFeatures.adultCatalogs,
  );

  @visibleForTesting
  AdultAccess.forTesting({required this.supported});

  final bool supported;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);
  String? _profileId;
  bool _listening = false;
  int _generation = 0;

  bool get blockedForKids =>
      ProfileRepository.instance.activeIsKids ||
      ParentalControls.instance.kidsMode.value;

  bool get canAccess =>
      supported &&
      enabled.value &&
      unlocked.value &&
      _profileId == ActiveProfile.instance.id &&
      !blockedForKids;

  static String _key(String id) => 'novatube.adult.enabled.$id';

  Future<void> load() async {
    if (!_listening) {
      _listening = true;
      ActiveProfile.instance.listenable.addListener(_onProfileChanged);
      ParentalControls.instance.kidsMode.addListener(_onKidsChanged);
    }
    final String id = ActiveProfile.instance.id;
    if (_profileId != id) {
      lock();
      enabled.value = false;
    }
    final int generation = ++_generation;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (generation != _generation || id != ActiveProfile.instance.id) return;
    _profileId = id;
    enabled.value = supported && (prefs.getBool(_key(id)) ?? false);
    if (blockedForKids || !enabled.value) lock();
  }

  void _onProfileChanged() {
    // Le profil suivant ne voit jamais l'état autorisé du précédent.
    lock();
    enabled.value = false;
    _profileId = null;
    unawaited(load());
  }

  void _onKidsChanged() {
    if (blockedForKids) lock();
  }

  Future<bool> enableWithPin(String pin) async {
    final String id = ActiveProfile.instance.id;
    await load();
    if (!supported || blockedForKids || id != ActiveProfile.instance.id)
      return false;
    if (!await AppPinSettings.instance.verify(pin)) return false;
    if (id != ActiveProfile.instance.id || blockedForKids) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (id != ActiveProfile.instance.id || blockedForKids) return false;
    await prefs.setBool(_key(id), true);
    if (id != ActiveProfile.instance.id || blockedForKids) return false;
    _profileId = id;
    enabled.value = true;
    unlocked.value = true;
    return true;
  }

  Future<bool> unlockWithPin(String pin) async {
    final String id = ActiveProfile.instance.id;
    await load();
    if (!supported ||
        !enabled.value ||
        blockedForKids ||
        id != ActiveProfile.instance.id) return false;
    if (!await AppPinSettings.instance.verify(pin)) return false;
    if (id != ActiveProfile.instance.id || blockedForKids) return false;
    unlocked.value = true;
    return true;
  }

  Future<void> disable() async {
    final String id = ActiveProfile.instance.id;
    lock();
    enabled.value = false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }

  void lock() => unlocked.value = false;

  @visibleForTesting
  void dispose() {
    if (_listening) {
      ActiveProfile.instance.listenable.removeListener(_onProfileChanged);
      ParentalControls.instance.kidsMode.removeListener(_onKidsChanged);
    }
    _generation++;
    enabled.dispose();
    unlocked.dispose();
  }
}
