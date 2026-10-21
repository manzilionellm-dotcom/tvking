import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

void main() {
  tearDown(() {
    CastPlatform.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
    AppPlatform.isTv = false;
  });

  test('les entrées 7 MOTION et Windows existantes restent autorisées', () {
    expect(CastPlatform.zunoEdition, isNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(CastPlatform.canSend, isTrue);
    expect(CastPlatform.supports(CastDeviceKind.googleCast), isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(CastPlatform.canSend, isTrue);
    expect(CastPlatform.supports(CastDeviceKind.dlna), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.roku), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.googleCast), isFalse);
  });

  test('édition télévision : aucun transport proposé, même sur un PC', () {
    CastPlatform.configureZuno(ZunoEdition.television);
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(CastPlatform.canSend, isFalse);
      for (final kind in CastDeviceKind.values) {
        expect(CastPlatform.supports(kind), isFalse);
      }
    }
  });

  for (final size in [const Size(390, 844), const Size(1600, 1000)]) {
    testWidgets('téléphone / grande tablette $size : Cast tactile autorisé', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Le panel continue de reconnaître ZUNO sous son identité historique.
      // Cette identité et la largeur ne doivent pas masquer le Cast tactile.
      AppPlatform.isTv = true;
      CastPlatform.configureZuno(ZunoEdition.touch);
      expect(CastPlatform.canSend, isTrue);
      expect(CastPlatform.supports(CastDeviceKind.googleCast), isTrue);
      expect(CastPlatform.supports(CastDeviceKind.dlna), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  test('ZUNO ordinateur garde DLNA/Roku avec son identité panel TV', () {
    AppPlatform.isTv = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    CastPlatform.configureZuno(ZunoEdition.desktop);
    expect(CastPlatform.canSend, isTrue);
    expect(CastPlatform.supports(CastDeviceKind.dlna), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.roku), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.chromecast), isFalse);
    expect(CastPlatform.supports(CastDeviceKind.googleCast), isFalse);
  });
}
