import 'dart:isolate';

/// Un lot reste en vol jusqu'à son écriture SQLite. Sans cet accusé,
/// SendPort.send empile tout le guide en RAM si le disque est lent.
class EpgRowBatch {
  const EpgRowBatch(this.rows, this.acknowledge);

  final List<Map<String, Object?>> rows;
  final SendPort acknowledge;
}

Future<void> sendEpgRows(
  SendPort destination,
  List<Map<String, Object?>> rows,
) async {
  final ReceivePort ack = ReceivePort();
  try {
    destination.send(EpgRowBatch(rows, ack.sendPort));
    await ack.first;
  } finally {
    ack.close();
  }
}
