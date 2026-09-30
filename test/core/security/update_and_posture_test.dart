import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/security/device_posture.dart';
import 'package:tv_king/core/security/update_digest.dart';

void main() {
  test('sans empreinte annoncée, la mise à jour n\'est pas refusée', () {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    expect(apkDigestOk(bytes, ''), isTrue);
    expect(apkDigestOk(bytes, 'zz'), isFalse);
    expect(apkDigestOk(bytes, sha256Hex(bytes)), isTrue);
    final Uint8List other = Uint8List.fromList(<int>[9]);
    expect(apkDigestOk(other, sha256Hex(bytes)), isFalse);
  });

  test('le manifeste ancien, sans sha256, laisse le champ vide', () {
    expect(
      sha256FromManifest(<String, dynamic>{'versionCode': 1}),
      '',
    );
    final Map<String, dynamic>? parsed = decodeManifest(
      '{"versionCode": 2, "sha256": "AB"}',
    );
    expect(sha256FromManifest(parsed!), 'ab');
    expect(decodeManifest('['), isNull);
  });

  test('la posture inhabituelle est notée, jamais un motif de blocage', () {
    const DevicePosture quiet = DevicePosture.unknown;
    expect(quiet.noteworthy, isFalse);
    expect(quiet.releaseBuild, isTrue);
    final DevicePosture rooted = DevicePosture.fromMap(<Object?, Object?>{
      'suPresent': true,
      'emulator': false,
    });
    expect(rooted.noteworthy, isTrue);
    expect(rooted.suPresent, isTrue);
    expect(rooted.releaseBuild, isTrue);
  });
}
