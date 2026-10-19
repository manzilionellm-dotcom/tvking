import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/epg_batch_pipe.dart';

/// Un vrai isolate produit trois lots. Le disque est simulé par le test,
/// qui retient chaque accusé aussi longtemps qu'il veut.
Future<void> _produce(SendPort port) async {
  for (int i = 0; i < 3; i++) {
    await sendEpgRows(port, <Map<String, Object?>>[
      <String, Object?>{'channel_id': 'channel-$i'},
    ]);
  }
  port.send('done');
}

void main() {
  test('un disque lent ne laisse jamais plusieurs lots en vol', () async {
    final ReceivePort port = ReceivePort();
    final List<Object?> received = <Object?>[];
    final List<Completer<EpgRowBatch>> batches = List<Completer<EpgRowBatch>>
        .generate(3, (_) => Completer<EpgRowBatch>());
    final Completer<void> done = Completer<void>();
    int next = 0;
    final StreamSubscription<Object?> subscription = port.listen((Object? msg) {
      received.add(msg);
      if (msg is EpgRowBatch) batches[next++].complete(msg);
      if (msg == 'done') done.complete();
    });
    final Isolate worker = await Isolate.spawn(_produce, port.sendPort);
    try {
      for (int i = 0; i < 3; i++) {
        final EpgRowBatch batch = await batches[i].future;
        await pumpEventQueue();
        expect(received.length, i + 1,
            reason: 'le lot suivant attend la fin de l’écriture');
        expect(batch.rows.single['channel_id'], 'channel-$i');
        batch.acknowledge.send(null);
      }
      await done.future;
      expect(received.length, 4);
    } finally {
      worker.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  });
}
