import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/cast_device.dart';

/// Le moteur réseau de 7 MOTION fonctionne sur PC. Le pont Google Cast
/// utilise le SDK Android sur mobile et Cast v2 sur le bureau.
abstract final class CastPlatform {
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool _androidHandset = false;

  /// Le type vient du matériel Android, jamais de la taille de la fenêtre.
  /// Une TV ne devient donc pas un téléphone avec une souris ou un écran réduit.
  static bool get isAndroidHandset => (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _androidHandset);
  static bool get canSendFromZuno => isWindows || isAndroidHandset;

  /// Le plugin croise le matériel avec l'édition signée du paquet :
  /// ZUNO TV ne peut jamais émettre ; ZUNO Mobile garde le Cast tactile.
  /// Les anciens paquets adaptatifs conservent leur détection matérielle.
  static Future<void> initializeZuno() async {
    _androidHandset = false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _androidHandset =
          await const MethodChannel('com.sevenmotion.zuno/cast-capability')
                  .invokeMethod<bool>('isHandset')
                  .timeout(const Duration(seconds: 2)) ==
              true;
    } catch (_) {/* Ancien binaire : on ne présente pas un pont inexistant. */}
  }

  static bool supports(CastDeviceKind kind) =>
      true; // Native SDK on Android; pure-Dart protocols on Windows.
}
