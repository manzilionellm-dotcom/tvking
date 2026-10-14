import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/desktop/playback_queue.dart';

void main() {
  test('un zap remplacé pendant une ouverture ne joue plus', () async {
    final List<String> calls = <String>[];
    final Completer<void> opening = Completer<void>();
    final Completer<void> entered = Completer<void>();
    final PlaybackQueue queue = PlaybackQueue(onError: (e, s) => fail('$e'));
    final int first = queue.replace();
    queue.enqueue(() async {
      entered.complete();
      await opening.future;
      if (queue.isCurrent(first)) calls.add('ancien');
    }, generation: first);
    await entered.future;
    final int last = queue.replace();
    final Completer<void> done = Completer<void>();
    queue.enqueue(() async {
      calls.add('nouveau');
      done.complete();
    }, generation: last);
    opening.complete();
    await done.future;
    await queue.close(() async {});
    expect(calls, <String>['nouveau']);
  });

  test('fermer attend le natif et annule toute commande en attente', () async {
    final List<String> calls = <String>[];
    final Completer<void> gate = Completer<void>();
    final Completer<void> entered = Completer<void>();
    final PlaybackQueue queue = PlaybackQueue(onError: (e, s) => fail('$e'));
    queue.enqueue(() async {
      entered.complete();
      await gate.future;
      calls.add('fin');
    });
    await entered.future;
    queue.enqueue(() async {
      calls.add('ne doit pas jouer');
    });
    final Future<void> closing = queue.close(() async {
      calls.add('libéré');
    });
    gate.complete();
    await closing;
    await queue.close(() async {
      calls.add('double libération');
    });
    expect(calls, <String>['fin', 'libéré']);
  });

  test('une erreur de commande ne casse pas la file suivante', () async {
    int errors = 0;
    final Completer<void> done = Completer<void>();
    final PlaybackQueue queue = PlaybackQueue(onError: (e, s) => errors++);
    queue.enqueue(() async {
      throw StateError('moteur');
    });
    queue.enqueue(() async {
      done.complete();
    });
    await done.future;
    await queue.close(() async {});
    expect(errors, 1);
  });
}
