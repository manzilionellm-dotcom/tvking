import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_service.dart';

void main() {
  tearDown(() => UpdateService.enabled = true);

  test('un artefact isolé ne vérifie, télécharge ni installe un client',
      () async {
    expect(UpdateService.enabled, isTrue);
    UpdateService.enabled = false;
    const update = UpdateInfo(
      versionCode: 1,
      versionName: 'test',
      url: 'https://example.invalid/test.apk',
      sha256: 'synthetic',
      sizeBytes: 1,
    );
    expect(await UpdateService.instance.check(), isNull);
    expect(await UpdateService.instance.prefetch(update), isNull);
    expect(await UpdateService.instance.downloadAndInstall(update), isFalse);
  });
}
