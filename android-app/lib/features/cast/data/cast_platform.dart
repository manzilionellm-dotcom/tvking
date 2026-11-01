import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/cast_device.dart';

/// Le moteur réseau de 7 MOTION fonctionne sur PC. Le pont Google Cast
/// reste un SDK Android : on ne présente jamais un appareil non pilotable.
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

  /// Le même paquet ZUNO peut être installé sur téléphone ou télévision.
  /// Le plugin décide si l'appareil peut émettre ; sa MAC reste inchangée.
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
      !isWindows || kind == CastDeviceKind.dlna || kind == CastDeviceKind.roku;
}
