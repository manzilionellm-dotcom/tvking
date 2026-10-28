import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/cast_device.dart';

/// Le moteur réseau de 7 MOTION fonctionne sur PC. Le pont Google Cast
/// reste un SDK Android : on ne présente jamais un appareil non pilotable.
abstract final class CastPlatform {
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool _androidHandset = false;
  static bool get canSendFromZuno => isWindows ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && _androidHandset);

  /// La variante TV peut être installée sur un téléphone. On demande le type
  /// matériel au plugin, sans modifier sa MAC ni la plateforme du heartbeat.
  static Future<void> initializeZuno() async {
    _androidHandset = false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _androidHandset = await const MethodChannel('com.sevenmotion.zuno/cast-capability')
          .invokeMethod<bool>('isHandset').timeout(const Duration(seconds: 2)) == true;
    } catch (_) { /* Ancien binaire : on ne présente pas un pont inexistant. */ }
  }

  static bool supports(CastDeviceKind kind) => !isWindows ||
      kind == CastDeviceKind.dlna || kind == CastDeviceKind.roku;
}
