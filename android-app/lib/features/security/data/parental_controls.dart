// =========================================================
//  parental_controls.dart — Contrôle parental & Mode Enfants
// =========================================================
//  Fonctionnalité « premium famille » (comme Netflix Kids / Disney+ Junior) :
//  un MODE ENFANTS qui masque automatiquement tout le contenu Adulte, protégé
//  par le code PIN à 4 chiffres de l'app (AppPinSettings). Un enfant ne peut
//  donc pas le désactiver lui-même.
//
//  Tout est LOCAL (SharedPreferences) — aucune dépendance réseau, aucun impact
//  sur les réglages du lecteur vidéo. ZUNO attend la confirmation du profil
//  et de ses restrictions avant d'afficher le catalogue. Le chemin historique
//  des autres applications reste désactivé jusqu'à l'activation par le parent.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/app_platform.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_policies.dart';

enum ParentalReadiness { loading, ready, failed }

class ParentalControls {
  ParentalControls._();
  static final ParentalControls instance = ParentalControls._();

  @visibleForTesting
  static Future<SharedPreferences> Function()? preferencesForTesting;

  /// État du Mode Enfants, OBSERVABLE : les écrans (ex. Direct) écoutent ce
  /// notifier pour se re-filtrer instantanément quand le parent bascule.
  /// Défaut historique : false. Le démarrage ZUNO ferme cet état avant
  /// toute lecture asynchrone, puis applique uniquement un résultat confirmé.
  ///
  /// La case est PAR PROFIL. Le profil 1 relit l'ancienne clé
  /// `security.kids_mode.v1`. Sur le profil Enfants, le mode est
  /// forcé : [setKidsMode](false) ne fait rien.
  final ValueNotifier<bool> kidsMode = ValueNotifier<bool>(false);

  bool _zunoProtection = false;
  final ValueNotifier<ParentalReadiness> readiness =
      ValueNotifier<ParentalReadiness>(ParentalReadiness.loading);
  String? _readProfile;
  int? _readScope;
  bool? _readProfileKids;
  bool get protectsZuno => AppPlatform.isZuno && _zunoProtection;
  int get contentGeneration => _gen;
  bool get contentReady => !protectsZuno ||
      (readiness.value == ParentalReadiness.ready &&
       _readProfile == ActiveProfile.instance.id &&
       _readScope == ActiveProfile.instance.scopeListenable.value &&
       ProfileRepository.instance.activeProfileConfirmed);

  /// Ferme les permissions avant toute attente disque. Cette protection
  /// obligatoire ne possède aucun interrupteur permettant de l'ouvrir.
  void protectZunoBeforeProfile() {
    _zunoProtection = true;
    _listen();
    _close();
  }

  void _close() {
    ++_gen;
    readiness.value = ParentalReadiness.loading;
    kidsMode.value = true;
  }

  /// Le budget limite seulement l'attente de runApp, jamais les protections.
  Future<void> loadBeforeFirstFrame({
    Duration budget = const Duration(milliseconds: 300),
  }) async {
    final Future<void> pending = load();
    if (budget == Duration.zero) { unawaited(pending); return; }
    await pending.timeout(budget, onTimeout: () {});
  }

  Future<void> retry() async {
    _close();
    await ProfileRepository.instance.retryProtectedRead();
    await load();
  }

  bool _listening = false;
  int _gen = 0;

  /// Charge l'état du profil en cours. Se rebranche tout seul
  /// quand on change de profil. Best-effort (ne plante jamais).
  Future<void> load() async {
    if (AppPlatform.isZuno && !_zunoProtection) protectZunoBeforeProfile();
    _listen();
    await _read();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    void kick() {
      // Un renommage ou le choix « demander au démarrage » ne change aucun
      // droit. Éviter de démonter une lecture pour cette notification seule.
      if (protectsZuno && contentReady &&
          _readProfileKids == ProfileRepository.instance.activeIsKids) {
        return;
      }
      unawaited(_read());
    }

    ActiveProfile.instance.listenable.addListener(kick);
    ProfileRepository.instance.addListener(kick);
    ActiveProfile.instance.scopeListenable.addListener(() {
      if (AppPlatform.isZuno) kick();
    });
  }

  Future<void> _read() {
    // Une notification de profil peut précéder l'appel explicite de main.
    // Elle doit fermer les permissions ZUNO, jamais lancer le chemin ancien.
    if (AppPlatform.isZuno && !_zunoProtection) protectZunoBeforeProfile();
    return protectsZuno ? _readProtected() : _readLegacy();
  }

  Future<void> _readProtected() async {
    _close();
    final int generation = _gen;
    try {
      final profiles = ProfileRepository.instance;
      await profiles.load();
      if (generation != _gen || !protectsZuno) return;
      if (!profiles.activeProfileConfirmed) {
        throw StateError('Profil non confirmé');
      }
      final String id = ActiveProfile.instance.id;
      final int scope = ActiveProfile.instance.scopeListenable.value;
      final bool profileKids = profiles.activeIsKids;
      final prefs = await (preferencesForTesting?.call() ?? SharedPreferences.getInstance());
      final bool stored = prefs.getBool(ProfileKeys.kidsMode(id)) ?? false;
      if (generation != _gen || !protectsZuno ||
          id != ActiveProfile.instance.id ||
          scope != ActiveProfile.instance.scopeListenable.value) {
        return;
      }
      _readProfile = id;
      _readScope = scope;
      _readProfileKids = profileKids;
      kidsMode.value = profileKids || stored;
      readiness.value = ParentalReadiness.ready;
    } catch (_) {
      if (generation != _gen || !protectsZuno) return;
      kidsMode.value = true;
      readiness.value = ParentalReadiness.failed;
    }
  }

  Future<void> _readLegacy() async {
    final int gen = ++_gen;
    final String id = ActiveProfile.instance.id;
    final bool kidsProfile = ProfileRepository.instance.profileById(id)?.isKids ?? false;
    bool stored = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Une lecture ancienne déjà en vol ne doit plus écrire après
      // l'activation de la protection ZUNO.
      if (AppPlatform.isZuno) return;
      stored = prefs.getBool(ProfileKeys.kidsMode(id)) ?? false;
      if (kidsProfile && !stored) {
        // Le profil Enfants démarre protégé, même au premier passage.
        await prefs.setBool(ProfileKeys.kidsMode(id), true);
      }
    } catch (_) {
      // best-effort : on applique quand même la règle (forcé si Enfants).
    }
    if (gen != _gen || protectsZuno) return;
    kidsMode.value = KidsProfilePolicy.effectiveKidsMode(
      isKidsProfile: kidsProfile,
      stored: stored,
    );
  }

  /// Active / désactive le Mode Enfants du profil en cours.
  /// Refusé sur le profil Enfants : il reste protégé.
  Future<void> setKidsMode(bool value) async {
    if (protectsZuno) return _setProtectedKidsMode(value);
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
  Future<void> _setProtectedKidsMode(bool value) async {
    if (!contentReady) return;
    if (!value && ProfileRepository.instance.activeIsKids) {
      kidsMode.value = true;
      return;
    }
    final int generation = ++_gen;
    final String profile = ActiveProfile.instance.id;
    final int scope = ActiveProfile.instance.scopeListenable.value;
    // Fermer est immédiat ; ouvrir attend la confirmation de l'écriture
    // déjà demandée par l'utilisateur dans les réglages.
    if (value) kidsMode.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool saved = await prefs.setBool(ProfileKeys.kidsMode(profile), value);
      if (generation != _gen || profile != ActiveProfile.instance.id ||
          scope != ActiveProfile.instance.scopeListenable.value) {
        return;
      }
      if (!saved) throw StateError('Préférence non enregistrée');
      kidsMode.value = ProfileRepository.instance.activeIsKids || value;
    } catch (_) {
      if (generation != _gen) return;
      kidsMode.value = true;
      readiness.value = ParentalReadiness.failed;
    }
  }

  @visibleForTesting
  void resetProtectionForTesting() {
    _zunoProtection = false;
    preferencesForTesting = null;
    ++_gen;
    _readProfile = null;
    _readScope = null;
    _readProfileKids = null;
    readiness.value = ParentalReadiness.loading;
    kidsMode.value = false;
  }

}
