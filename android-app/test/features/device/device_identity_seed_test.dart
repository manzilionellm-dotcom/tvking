import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/device/domain/device_identity_seed.dart';

void main() {
  test(
    'la TV et les anciens produits conservent la graine de leur licence',
    () {
      for (final edition in ['', 'auto', 'tv']) {
        expect(
          deviceIdentitySeed('android-stable', edition: edition),
          'android-stable',
        );
      }
    },
  );
  test('le mobile séparé reste stable sans partager la MAC de la TV', () {
    final mobile = deviceIdentitySeed('android-stable', edition: 'mobile');
    expect(mobile, 'android-stable:zuno-mobile:v1');
    expect(mobile, deviceIdentitySeed('android-stable', edition: 'mobile'));
    expect(mobile, isNot(deviceIdentitySeed('android-stable', edition: 'tv')));
    expect(deviceIdentitySeed('', edition: 'mobile'), isEmpty);
  });
}
