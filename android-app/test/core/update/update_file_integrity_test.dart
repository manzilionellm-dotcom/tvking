import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_file_integrity.dart';

void main() {
  test('le cache remplacé à taille identique est refusé', () async {
    final Directory temp =
        await Directory.systemTemp.createTemp('zuno-update-test-');
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}/app.apk');
    const String abcSha =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    await file.writeAsString('abc');
    expect(await updateFileMatches(file, sizeBytes: 3, sha256: abcSha), isTrue);
    await file.writeAsString('xyz');
    expect(
        await updateFileMatches(file, sizeBytes: 3, sha256: abcSha), isFalse);
    await file.writeAsString('ab');
    expect(
        await updateFileMatches(file, sizeBytes: 3, sha256: abcSha), isFalse);
    await file.delete();
    expect(
        await updateFileMatches(file, sizeBytes: 3, sha256: abcSha), isFalse);
  });
}
