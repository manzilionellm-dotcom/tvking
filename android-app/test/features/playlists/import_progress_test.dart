import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';

void main() {
  setUp(ImportProgressBus.clear);
  tearDown(ImportProgressBus.clear);

  test('un petit import ne perd aucun changement d’étape', () {
    final stages = <ImportStage>[];
    void record() => stages.add(ImportProgressBus.current.value!.stage);
    ImportProgressBus.current.addListener(record);
    addTearDown(() => ImportProgressBus.current.removeListener(record));

    // Tous ces faits peuvent arriver dans les mêmes 120 ms sur un bon réseau.
    ImportProgressBus.connecting();
    ImportProgressBus.downloading(1024);
    ImportProgressBus.decoding(1024);
    ImportProgressBus.found(2000);
    ImportProgressBus.saving(1000, 2000);
    ImportProgressBus.saving(2000, 2000);
    ImportProgressBus.done(2000);

    expect(stages, <ImportStage>[
      ImportStage.connecting, ImportStage.downloading, ImportStage.decoding,
      ImportStage.found, ImportStage.saving, ImportStage.saving, ImportStage.done,
    ]);
    expect(ImportProgressBus.current.value!.count, 2000);
  });

  test('les paquets de la même étape restent limités, sans gonfler les chiffres', () {
    ImportProgressBus.downloading(1024);
    for (int i = 2; i < 100; i++) {
      ImportProgressBus.downloading(i * 1024);
    }
    expect(ImportProgressBus.current.value!.bytes, 1024);
    ImportProgressBus.clear();
    expect(ImportProgressBus.current.value, isNull);
    ImportProgressBus.downloading(64);
    expect(ImportProgressBus.current.value!.bytes, 64);
  });
}
