import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/device/data/device_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.manzilionellm.tvking/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'une erreur ou une fiche native vide ne reste pas figée pour la session',
    () async {
      int reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getDeviceInfo');
        reads++;
        if (reads == 1) throw PlatformException(code: 'not_ready');
        if (reads == 2) return null;
        if (reads == 3) return <String, String>{};
        if (reads == 4)
          return <String, String>{'deviceKind': 'unknown', 'model': ' '};
        return <String, String>{
          'deviceKind': 'android_phone',
          'model': 'SM-S938B',
          'manufacturer': 'Samsung',
          'release': '16',
          'sdk': '36',
          'build': 'test-build',
        };
      });
      try {
        final identity = DeviceIdentity.instance;
        expect(await identity.deviceInfo(), isEmpty);
        expect(await identity.deviceInfo(), isEmpty);
        expect(await identity.deviceInfo(), isEmpty);
        expect((await identity.deviceInfo())['deviceKind'], 'unknown');
        final info = await identity.deviceInfo();
        expect(info['model'], 'SM-S938B');
        expect(info['deviceKind'], 'android_phone');
        expect(await identity.deviceInfo(), info);
        expect(
          reads,
          5,
          reason: 'La fiche complète est ensuite gardée en cache.',
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
