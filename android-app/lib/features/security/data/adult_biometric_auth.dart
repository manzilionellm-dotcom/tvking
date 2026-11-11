import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Résultat fermé par défaut : seul [AdultBiometricResult.authenticated] autorise la suite.
enum AdultBiometricResult {
  authenticated,
  unavailable,
  notEnrolled,
  cancelled,
  rejected,
  lockedOut,
  error,
}

/// Frontière injectable pour tester les refus et les réponses tardives sans
/// simuler une autorisation en modifiant directement les états de l'accès.
abstract interface class AdultBiometricAuthenticator {
  Future<AdultBiometricResult> authenticate({required String reason});
  Future<void> cancel();
}

/// Authentification réservée à l'espace +18 de NOVATUBE. Le wrapper historique
/// BiometricAuth conserve son comportement pour les autres parcours.
class SystemAdultBiometrics implements AdultBiometricAuthenticator {
  SystemAdultBiometrics({
    @visibleForTesting LocalAuthentication? authentication,
  }) : _auth = authentication ?? LocalAuthentication();

  final LocalAuthentication _auth;
  int _generation = 0;

  @override
  Future<AdultBiometricResult> authenticate({required String reason}) async {
    final int generation = ++_generation;
    try {
      // isDeviceSupported peut aussi accepter un simple code appareil : ce
      // n'est pas une preuve de disponibilité biométrique et on ne l'utilise pas.
      final bool available = await _auth.canCheckBiometrics;
      if (generation != _generation) return AdultBiometricResult.cancelled;
      if (!available) return AdultBiometricResult.unavailable;

      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      if (generation != _generation) return AdultBiometricResult.cancelled;
      if (enrolled.isEmpty) return AdultBiometricResult.notEnrolled;

      // Android choisit la biométrie compatible (empreinte, visage…). Aucun
      // PIN, schéma ou mot de passe appareil ne peut remplacer cette étape.
      final bool accepted = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
          useErrorDialogs: false,
          sensitiveTransaction: true,
        ),
      );
      if (generation != _generation) return AdultBiometricResult.cancelled;
      return accepted
          ? AdultBiometricResult.authenticated
          : AdultBiometricResult.rejected;
    } on PlatformException catch (error) {
      if (generation != _generation) return AdultBiometricResult.cancelled;
      switch (error.code) {
        case auth_error.notAvailable:
        case auth_error.otherOperatingSystem:
        case auth_error.biometricOnlyNotSupported:
          return AdultBiometricResult.unavailable;
        case auth_error.notEnrolled:
        case auth_error.passcodeNotSet:
          return AdultBiometricResult.notEnrolled;
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return AdultBiometricResult.lockedOut;
        default:
          return AdultBiometricResult.error;
      }
    } catch (_) {
      return generation == _generation
          ? AdultBiometricResult.error
          : AdultBiometricResult.cancelled;
    }
  }

  @override
  Future<void> cancel() async {
    // L'invalidation précède l'appel natif : un succès déjà en transit ne
    // redevient jamais valide, même si stopAuthentication ne peut plus l'arrêter.
    _generation++;
    try {
      await _auth.stopAuthentication();
    } catch (_) {
      // L'accès Dart reste fermé indépendamment du résultat de l'annulation.
    }
  }
}
