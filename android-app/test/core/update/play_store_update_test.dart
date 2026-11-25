import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tv_king/core/update/play_store_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(launcher, null));

  void package(String id) => PackageInfo.setMockInitialValues(
      appName: 'ZUNO',
      packageName: id,
      version: '113',
      buildNumber: '1793555495',
      buildSignature: '');

  for (final id in [
    'com.sevenmotion.tv.seven_tv',
    'com.manzilionellm.tvking'
  ]) {
    test('ouvre la fiche existante du paquet $id, sans télécharger un APK',
        () async {
      package(id);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(launcher, (call) async {
        calls.add(call);
        return true;
      });
      expect(await openPlayStoreUpdate(), isTrue);
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['url'],
          'https://play.google.com/store/apps/details?id=$id');
    });
  }

  for (final throws in [false, true]) {
    test(
        'Store indisponible : signale un échec et autorise un nouvel essai ($throws)',
        () async {
      package('com.sevenmotion.tv.seven_tv');
      int calls = 0;
      messenger.setMockMethodCallHandler(launcher, (_) async {
        if (++calls > 1) return true;
        if (throws) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
        return false;
      });
      expect(await openPlayStoreUpdate(), isFalse);
      expect(await openPlayStoreUpdate(), isTrue);
    });
  }

  test('ne choisit aucune autre application si le paquet est inconnu',
      () async {
    package('');
    int calls = 0;
    messenger.setMockMethodCallHandler(launcher, (_) async {
      calls++;
      return true;
    });
    expect(await openPlayStoreUpdate(), isFalse);
    expect(calls, 0);
  });
}
