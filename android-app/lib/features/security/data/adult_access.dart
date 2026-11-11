import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/novatube_private_features.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import 'adult_biometric_auth.dart';
import 'parental_controls.dart';

/// Activation persistante par profil ; biométrie obligatoire à chaque visite.
/// Seule l'activation est mémorisée, jamais une session ni une preuve biométrique.
class AdultAccess with WidgetsBindingObserver {
  AdultAccess._({required this.supported})
    : _biometrics = SystemAdultBiometrics();
  static final AdultAccess instance = AdultAccess._(
    supported: NovatubePrivateFeatures.adultCatalogs,
  );

  @visibleForTesting
  AdultAccess.forTesting({
    required this.supported,
    AdultBiometricAuthenticator? biometrics,
  }) : _biometrics = biometrics ?? SystemAdultBiometrics();

  final bool supported;
  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _unlocked = ValueNotifier<bool>(false);

  /// Les écrans observent les états ; seul ce contrôleur peut les autoriser.
  ValueListenable<bool> get enabled => _enabled;
  ValueListenable<bool> get unlocked => _unlocked;
  AdultBiometricAuthenticator _biometrics;
  AdultBiometricResult? lastBiometricResult;
  String? _profileId;
  bool _listening = false;
  bool _disposed = false;
  bool _authenticating = false;
  bool _backgrounded = false;
  int _loadGeneration = 0;
  int _authGeneration = 0;

  bool get authenticating => _authenticating;

  bool get blockedForKids =>
      ProfileRepository.instance.activeIsKids ||
      ParentalControls.instance.kidsMode.value;

  bool get canAccess =>
      !_disposed &&
      supported &&
      enabled.value &&
      unlocked.value &&
      !_backgrounded &&
      _profileId == ActiveProfile.instance.id &&
      !blockedForKids;

  static String _key(String id) => 'novatube.adult.enabled.$id';

  Future<void> load() async {
    if (_disposed) return;
    if (!_listening) {
      _listening = true;
      ActiveProfile.instance.listenable.addListener(_onProfileChanged);
      ParentalControls.instance.kidsMode.addListener(_onKidsChanged);
      WidgetsBinding.instance.addObserver(this);
      _backgrounded = _isBackground(WidgetsBinding.instance.lifecycleState);
    }
    final String id = ActiveProfile.instance.id;
    if (_profileId != id) {
      if (_profileId != null) lock();
      _enabled.value = false;
      _unlocked.value = false;
      _profileId = id;
    }
    final int generation = ++_loadGeneration;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_disposed ||
        generation != _loadGeneration ||
        id != ActiveProfile.instance.id)
      return;
    _enabled.value = supported && (prefs.getBool(_key(id)) ?? false);
    if (blockedForKids || (!enabled.value && unlocked.value)) lock();
  }

  void _onProfileChanged() {
    // Le changement invalide aussi une réponse biométrique encore en transit,
    // y compris si l'utilisateur revient aussitôt au profil précédent.
    lock();
    _enabled.value = false;
    _profileId = null;
    unawaited(load());
  }

  void _onKidsChanged() {
    if (blockedForKids) lock();
  }

  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // BiometricPrompt peut rendre Flutter inactive sans cacher l'application.
    // Ce seul état ne doit pas annuler le dialogue système. Dès que l'app est
    // réellement cachée, toute session et toute authentification sont annulées.
    if (_isBackground(state)) {
      _backgrounded = true;
      lock();
    } else if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
    }
  }

  Future<bool> enableWithBiometrics({
    required bool consent,
    required String reason,
  }) => _authorize(activating: true, consent: consent, reason: reason);

  Future<bool> unlockWithBiometrics({required String reason}) =>
      _authorize(activating: false, consent: false, reason: reason);

  bool _isCurrent(int generation, String profileId) =>
      !_disposed &&
      supported &&
      generation == _authGeneration &&
      profileId == ActiveProfile.instance.id &&
      _profileId == profileId &&
      !_backgrounded &&
      !blockedForKids;

  Future<bool> _authorize({
    required bool activating,
    required bool consent,
    required String reason,
  }) async {
    if (_disposed) return false;
    if (!supported || blockedForKids) {
      lock();
      return false;
    }
    if (_authenticating) return false;
    lock();
    final int generation = _authGeneration;
    final String profileId = ActiveProfile.instance.id;
    _authenticating = true;
    lastBiometricResult = null;
    try {
      await load();
      if (!_isCurrent(generation, profileId) ||
          (activating && !enabled.value && !consent) ||
          (!activating && !enabled.value))
        return false;

      final AdultBiometricResult result = await _biometrics.authenticate(
        reason: reason,
      );
      if (!_isCurrent(generation, profileId)) return false;
      lastBiometricResult = result;
      if (result != AdultBiometricResult.authenticated) return false;
      if (!activating && !enabled.value) return false;

      if (activating && !enabled.value) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        if (!_isCurrent(generation, profileId)) return false;
        final bool saved = await prefs.setBool(_key(profileId), true);
        if (!saved || !_isCurrent(generation, profileId)) {
          // Une annulation pendant l'écriture ne doit pas laisser derrière
          // elle une première activation que l'interface a refusée.
          await prefs.remove(_key(profileId));
          return false;
        }
        _enabled.value = true;
      }
      if (!_isCurrent(generation, profileId)) return false;
      _unlocked.value = true;
      return canAccess;
    } catch (_) {
      if (_isCurrent(generation, profileId)) {
        lastBiometricResult = AdultBiometricResult.error;
      }
      return false;
    } finally {
      _authenticating = false;
    }
  }

  /// Compatibilité des anciens appelants : aucun PIN, même correct, ne peut
  /// désormais ouvrir +18. Les autres contrôles parentaux gardent leur PIN.
  Future<bool> enableWithPin(String pin) async {
    lock();
    return false;
  }

  Future<bool> unlockWithPin(String pin) async {
    lock();
    return false;
  }

  Future<void> disable() async {
    final String id = ActiveProfile.instance.id;
    lock();
    _loadGeneration++;
    _enabled.value = false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }

  void lock() {
    if (_disposed) return;
    _authGeneration++;
    _unlocked.value = false;
    if (_authenticating) {
      lastBiometricResult = AdultBiometricResult.cancelled;
      unawaited(_cancelAuthentication());
    }
  }

  Future<void> _cancelAuthentication() async {
    try {
      await _biometrics.cancel();
    } catch (_) {
      // Une annulation native en échec ne rétablit jamais le jeton invalidé.
    }
  }

  @visibleForTesting
  void setBiometricsForTesting(AdultBiometricAuthenticator? biometrics) {
    if (!kDebugMode) throw StateError('Injection réservée aux tests');
    lock();
    _biometrics = biometrics ?? SystemAdultBiometrics();
  }

  @visibleForTesting
  void dispose() {
    lock();
    _disposed = true;
    if (_listening) {
      ActiveProfile.instance.listenable.removeListener(_onProfileChanged);
      ParentalControls.instance.kidsMode.removeListener(_onKidsChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    _loadGeneration++;
    _enabled.dispose();
    _unlocked.dispose();
  }
}
