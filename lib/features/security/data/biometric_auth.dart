// =========================================================
//  biometric_auth.dart — Wrapper local_auth
// =========================================================
//  Encapsule les appels au plugin `local_auth` :
//    - canCheckBiometrics() : le device a-t-il un capteur ?
//    - hasEnrolledBiometrics() : l'utilisateur a-t-il configuré
//      une empreinte / Face Unlock ?
//    - authenticate() : déclenche le dialog système de demande
//      d'auth, avec fallback automatique sur PIN/pattern/mot-de-passe
//      Android.
//
//  Le comportement avec `biometricOnly: false` :
//    1. Si empreinte/face configurée → dialog biométrie
//    2. Si user tape "annuler" ou foire X fois → Android propose
//       le PIN de l'écran de verrouillage
//    3. Si rien configuré (device sans lock) → le dialog est
//       skippé et authenticate() retourne true direct (Android
//       refuse de bloquer un device unprotected — c'est volontaire).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/branding/brand_config.dart';
import '../../../core/i18n/l10n_now.dart';

class BiometricAuth {
  BiometricAuth._();
  static final BiometricAuth instance = BiometricAuth._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Le device supporte-t-il un capteur biométrique ou un PIN
  /// système ? `false` sur les très vieux Android sans aucun
  /// hardware d'auth.
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[BioAuth] isSupported: ${e.message}');
      return false;
    }
  }

  /// Déclenche le dialog d'auth. Retourne `true` si l'utilisateur
  /// s'est authentifié avec succès, `false` si annulation ou échec.
  /// Ne throw jamais — fallback silent sur `false` en cas d'erreur.
  ///
  /// `reason` : texte affiché dans le dialog système. Si `null`,
  /// on prend « Déverrouille {appName} » dans la langue active
  /// (via l10nNow, hors widget) avec le nom de marque dynamique.
  Future<bool> authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ??
            l10nNow.lockUnlockReason(BrandConfig.instance.appName),
        options: const AuthenticationOptions(
          // false → permet le fallback PIN/pattern/mot-de-passe
          // système Android quand l'empreinte échoue ou n'est pas
          // configurée. Nettement plus user-friendly.
          biometricOnly: false,
          // L'auth doit persister tant que l'app est en foreground.
          // Évite des re-prompts sur des actions sensibles dans la
          // même session.
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[BioAuth] authenticate: ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }
}
