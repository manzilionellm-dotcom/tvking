import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/notifications/notification_service.dart';
import 'package:tv_king/core/update/build_flags.dart';
import 'package:tv_king/features/about/data/force_update_checker.dart';
import 'package:tv_king/features/about/data/update_checker.dart';
import 'package:tv_king/features/device/data/device_identity.dart';
import 'package:tv_king/features/vod/domain/content_partition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // Depuis la version 18, les tests doivent enregistrer explicitement
    // l'implémentation ; le vrai iPhone le fait via le registrant Flutter.
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() { debugDefaultTargetPlatformOverride = null; });

  test('canal Apple : aucune recherche de mise à jour APK', () async {
    expect(kIsAppStoreBuild, isTrue);
    expect(kIsPlayBuild, isTrue);
    expect(AppPlatform.id, 'mobile'); // Contrat actuel du panel d'activation.
    expect(await UpdateChecker.instance.check(), isNull);
    expect(await ForceUpdateChecker.instance.mustUpdate(), isFalse);
  });

  test('le catalogue public ne propose pas le rayon réservé 18+', () {
    expect(ContentPartition.visible('Channel', 'Adults', adultOnly: true), isFalse);
    expect(ContentPartition.visible('Channel', 'News', adultOnly: false), isTrue);
  });

  test('une identité privée iOS est utilisée sans annoncer un ANDROID_ID', () async {
    const channel = MethodChannel('com.manzilionellm.tvking/device');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getInstallId') return 'ios-private-installation-id';
      throw PlatformException(code: 'unexpected_method');
    });
    final mac = await DeviceIdentity.instance.mac;
    expect(mac, matches(RegExp(r'^MK:([0-9A-F]{2}:){4}[0-9A-F]{2}$')));
    expect(calls, contains('getInstallId'));
    expect(await DeviceIdentity.instance.androidId(), isEmpty);
    expect(calls, isNot(contains('getAndroidId')));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('les notifications iOS respectent un refus de permission', () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    bool requested = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermissions') { requested = true; return false; }
      return true;
    });
    expect(await NotificationService.instance.requestPermission(), isFalse);
    expect(requested, isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
