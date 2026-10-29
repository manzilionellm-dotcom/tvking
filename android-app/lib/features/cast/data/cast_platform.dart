import 'package:flutter/foundation.dart';
import '../domain/cast_device.dart';

/// Le moteur réseau de 7 MOTION fonctionne sur PC. Le pont Google Cast
/// reste un SDK Android : on ne présente jamais un appareil non pilotable.
abstract final class CastPlatform {
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool supports(CastDeviceKind kind) => !isWindows ||
      kind == CastDeviceKind.dlna || kind == CastDeviceKind.roku;
}
