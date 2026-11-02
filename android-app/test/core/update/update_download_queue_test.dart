import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_download_queue.dart';

void main() {
  test('deux versions restent séquentielles et le même fichier est partagé',
      () async {
    final UpdateDownloadQueue<int> queue = UpdateDownloadQueue<int>();
    final Completer<int> first = Completer<int>();
    final Completer<int> second = Completer<int>();
    final List<int> started = <int>[];
    final Future<int> a = queue.run('version1-hash1', () {
      started.add(1);
      return first.future;
    });
    expect(identical(a, queue.run('version1-hash1', () async => 99)), isTrue);
    final Future<int> b = queue.run('version2-hash2', () {
      started.add(2);
      return second.future;
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, <int>[1]);
    first.complete(1);
    expect(await a, 1);
    await Future<void>.delayed(Duration.zero);
    expect(started, <int>[1, 2]);
    expect(identical(b, queue.run('version2-hash2', () async => 99)), isTrue,
        reason: 'la fin du premier ne doit pas effacer le deuxième');
    second.complete(2);
    expect(await b, 2);
  });

  test('une erreur ne bloque pas le téléchargement suivant ou une relance',
      () async {
    final UpdateDownloadQueue<int> queue = UpdateDownloadQueue<int>();
    final Future<int> failed =
        queue.run('old', () async => throw StateError('offline'));
    final Future<int> fresh = queue.run('new', () async => 2);
    await expectLater(failed, throwsStateError);
    expect(await fresh, 2);
    expect(await queue.run('old', () async => 3), 3);
  });
}
