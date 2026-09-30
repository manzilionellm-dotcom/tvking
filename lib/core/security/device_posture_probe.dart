// =========================================================
//  device_posture_probe.dart — Une note, pas une porte
// =========================================================
//  Demande la posture au plugin Android. Si le canal n'existe pas
//  (tests, bureau, vieille box), on reste sur [DevicePosture.unknown]
//  et la lecture continue. Un signal inhabituel est écrit UNE fois
//  dans la boîte noire. Personne ne s'en sert pour bloquer un client.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../observability/structured_logger.dart';
import 'device_posture.dart';

abstract final class DevicePostureProbe {
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  static bool _noted = false;

  /// Best-effort. Ne jette pas. Ne bloque pas.
  static Future<DevicePosture> read() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object>('getDevicePosture');
      if (raw is! Map) return DevicePosture.unknown;
      final DevicePosture posture = DevicePosture.fromMap(raw);
      if (posture.noteworthy && !_noted) {
        _noted = true;
        StructuredLogger.instance.warn(
          domain: 'security',
          event: 'device_posture',
          ctx: <String, Object>{
            'debugger': posture.debuggerConnected,
            'emulator': posture.emulator,
            'testKeys': posture.testKeys,
            'su': posture.suPresent,
          },
        );
      }
      return posture;
    } catch (e) {
      if (kDebugMode) debugPrint('[Posture] indisponible: $e');
      return DevicePosture.unknown;
    }
  }
}
