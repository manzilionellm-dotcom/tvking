// =========================================================
//  import_progress_test.dart — Modèle de progression d'import
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';

void main() {
  group('ImportProgress.downloadFraction', () {
    test('null quand la taille totale est inconnue (réponse chunked)', () {
      const ImportProgress p = ImportProgress(
        phase: ImportPhase.downloading,
        bytesReceived: 5000,
      );
      expect(p.downloadFraction, isNull);
    });

    test('fraction réelle quand la taille est connue', () {
      const ImportProgress p = ImportProgress(
        phase: ImportPhase.downloading,
        bytesReceived: 512,
        totalBytes: 1024,
      );
      expect(p.downloadFraction, 0.5);
    });

    test('bornée à 1.0 même si le serveur sous-estime la taille', () {
      const ImportProgress p = ImportProgress(
        phase: ImportPhase.downloading,
        bytesReceived: 2048,
        totalBytes: 1024,
      );
      expect(p.downloadFraction, 1.0);
    });

    test('totalBytes <= 0 → indéterminé (null), pas de division par zéro', () {
      const ImportProgress p = ImportProgress(
        phase: ImportPhase.downloading,
        bytesReceived: 10,
        totalBytes: 0,
      );
      expect(p.downloadFraction, isNull);
    });
  });

  group('ImportProgress.copyWith', () {
    test('remplace la phase en conservant le reste', () {
      const ImportProgress base = ImportProgress(
        phase: ImportPhase.analyzing,
        channelsFound: 1200,
      );
      final ImportProgress next = base.copyWith(phase: ImportPhase.done);
      expect(next.phase, ImportPhase.done);
      expect(next.channelsFound, 1200);
    });
  });
}
