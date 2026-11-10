// Une autorisation courte, locale et révocable pour l'espace Adultes.
// Aucun PIN ou renseignement biométrique n'est stocké dans ce module.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cast/data/cast_platform.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import 'parental_controls.dart';

bool _authenticating = false;

bool _eligible(String profileId, int scope) =>
    ActiveProfile.instance.id == profileId &&
    ActiveProfile.instance.scopeListenable.value == scope &&
    ProfileRepository.instance.profileById(profileId) != null &&
    !ProfileRepository.instance.profileById(profileId)!.isKids &&
    !ParentalControls.instance.kidsMode.value;

/// Le parent de l'espace possède cette autorisation et la révoque à sa
/// sortie. Direct et Cinéma l'écoutent sans la disposer eux-mêmes.
/// Un changement de profil, de listes ou de protection l'invalide pour de
/// bon : revenir ensuite au même profil ne rétablit jamais l'accès.
class AdultAccessGrant extends ChangeNotifier {
  AdultAccessGrant._(this._profileId, this._scope) {
    ActiveProfile.instance.scopeListenable.addListener(_check);
    ProfileRepository.instance.addListener(_check);
    ParentalControls.instance.kidsMode.addListener(_check);
  }

  final String _profileId;
  final int _scope;
  bool _revoked = false;
  bool _disposed = false;

  bool get isValid => !_revoked && _eligible(_profileId, _scope);

  void _check() {
    if (!isValid) revoke();
  }

  void _unlisten() {
    ActiveProfile.instance.scopeListenable.removeListener(_check);
    ProfileRepository.instance.removeListener(_check);
    ParentalControls.instance.kidsMode.removeListener(_check);
  }

  void revoke() {
    if (_revoked || _disposed) return;
    _revoked = true;
    _unlisten();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _revoked = true;
    _unlisten();
    _disposed = true;
    super.dispose();
  }
}

/// Utilise le PIN des réglages fourni par l'appelant sur TV, ou si le
/// téléphone n'a réellement aucune biométrie configurée. Une annulation,
/// un refus, un blocage ou une erreur système ne devient JAMAIS un repli.
Future<AdultAccessGrant?> authenticateAdultAccess({
  required String reason,
  required Future<bool> Function() confirmPin,
}) async {
  if (_authenticating || reason.trim().isEmpty) return null;
  _authenticating = true;
  final String profileId = ActiveProfile.instance.id;
  final int scope = ActiveProfile.instance.scopeListenable.value;
  bool invalidated = false;
  void watchProtection() {
    if (!_eligible(profileId, scope)) invalidated = true;
  }

  // Un aller-retour dans une protection pendant le dialogue n'autorise
  // pas sa vieille réponse à rouvrir l'espace après coup.
  ActiveProfile.instance.scopeListenable.addListener(watchProtection);
  ProfileRepository.instance.addListener(watchProtection);
  ParentalControls.instance.kidsMode.addListener(watchProtection);
  bool current() => !invalidated && _eligible(profileId, scope);

  Future<bool> storedProtectionAllows() async {
    if (!current()) return false;
    // Relire aussi la clé persistée : au démarrage le notifier peut encore
    // attendre son chargement. Une lecture impossible garde l'accès fermé.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return current() &&
        !(prefs.getBool(ProfileKeys.kidsMode(profileId)) ?? false);
  }

  try {
    await ProfileRepository.instance.load();
    if (ActiveProfile.instance.id != profileId ||
        ActiveProfile.instance.scopeListenable.value != scope) {
      return null;
    }
    await ParentalControls.instance.load();
    if (!await storedProtectionAllows()) return null;

    bool authenticated;
    // canSendFromZuno inclut aussi Windows ; seuls les téléphones Android
    // utilisent ici biometricOnly (non supporté par Windows Hello).
    final bool handset =
        CastPlatform.canSendFromZuno && CastPlatform.isAndroidHandset;
    if (!handset) {
      authenticated = await confirmPin();
    } else {
      final LocalAuthentication auth = LocalAuthentication();
      final bool hardware = await auth.canCheckBiometrics;
      if (!current()) return null;
      if (!hardware) {
        authenticated = await confirmPin();
      } else {
        final List<BiometricType> enrolled =
            await auth.getAvailableBiometrics();
        if (!current()) return null;
        try {
          // Sur Android, une liste "enrolled" vide peut aussi signaler un
          // lockout. Seule l'erreur explicite NotEnrolled confirme l'absence
          // d'inscription ; on ne transforme pas un lockout en accès PIN.
          authenticated = await auth.authenticate(
            localizedReason: reason,
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: false,
              useErrorDialogs: false,
              sensitiveTransaction: true,
            ),
          );
        } on PlatformException catch (error) {
          if (enrolled.isNotEmpty ||
              error.code != auth_error.notEnrolled ||
              !current()) {
            return null;
          }
          authenticated = await confirmPin();
        }
      }
    }
    if (!authenticated || !await storedProtectionAllows()) return null;
    return AdultAccessGrant._(profileId, scope);
  } catch (_) {
    // Ni erreur plugin ni exception du dialogue PIN ne peut autoriser.
    return null;
  } finally {
    ActiveProfile.instance.scopeListenable.removeListener(watchProtection);
    ProfileRepository.instance.removeListener(watchProtection);
    ParentalControls.instance.kidsMode.removeListener(watchProtection);
    _authenticating = false;
  }
}
