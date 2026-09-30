// =========================================================
//  parental_controls.dart — Contrôle parental & Mode Enfants
// =========================================================
//  Fonctionnalité « premium famille » (comme Netflix Kids / Disney+ Junior) :
//  un MODE ENFANTS qui masque automatiquement tout le contenu Adulte, protégé
//  par le code PIN à 4 chiffres de l'app (AppPinSettings). Un enfant ne peut
//  donc pas le désactiver lui-même.
//
//  Tout est LOCAL (SharedPreferences) — aucune dépendance réseau, aucun impact
//  sur le lecteur vidéo. Par défaut TOUT est désactivé : le comportement de
//  l'app ne change pour personne tant que le parent n'active pas le mode.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_policies.dart';

class ParentalControls {
  ParentalControls._();
  static final ParentalControls instance = ParentalControls._();

  /// État du Mode Enfants, OBSERVABLE : les écrans (ex. Direct) écoutent ce
  /// notifier pour se re-filtrer instantanément quand le parent bascule.
  /// Défaut : false (rien de masqué).
  ///
  /// La case est PAR PROFIL. Le profil 1 relit l'ancienne clé
  /// `security.kids_mode.v1`. Sur le profil Enfants, le mode est
  /// forcé : [setKidsMode](false) ne fait rien.
  final ValueNotifier<bool> kidsMode = ValueNotifier<bool>(false);

  bool _listening = false;
  int _gen = 0;

  /// Charge l'état du profil en cours. Se rebranche tout seul
  /// quand on change de profil. Best-effort (ne plante jamais).
  Future<void> load() async {
    _listen();
    await _read();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    void kick() {
      unawaited(_read());
    }

    ActiveProfile.instance.listenable.addListener(kick);
    ProfileRepository.instance.addListener(kick);
  }

  Future<void> _read() async {
    final int gen = ++_gen;
    final String id = ActiveProfile.instance.id;
    final bool kidsProfile = ProfileRepository.instance.profileById(id)?.isKids ?? false;
    bool stored = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      stored = prefs.getBool(ProfileKeys.kidsMode(id)) ?? false;
      if (kidsProfile && !stored) {
        // Le profil Enfants démarre protégé, même au premier passage.
        await prefs.setBool(ProfileKeys.kidsMode(id), true);
      }
    } catch (_) {
      // best-effort : on applique quand même la règle (forcé si Enfants).
    }
    if (gen != _gen) return;
    kidsMode.value = KidsProfilePolicy.effectiveKidsMode(
      isKidsProfile: kidsProfile,
      stored: stored,
    );
  }

  /// Active / désactive le Mode Enfants du profil en cours.
  /// Refusé sur le profil Enfants : il reste protégé.
  Future<void> setKidsMode(bool value) async {
    final bool kidsProfile = ProfileRepository.instance.activeIsKids;
    if (!KidsProfilePolicy.canDisableKidsMode(isKidsProfile: kidsProfile) && !value) {
      kidsMode.value = true;
      return;
    }
    final String id = ActiveProfile.instance.id;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileKeys.kidsMode(id), value);
    } catch (_) {
      // best-effort
    }
    kidsMode.value = KidsProfilePolicy.effectiveKidsMode(
      isKidsProfile: kidsProfile,
      stored: value,
    );
  }
}
