// =========================================================
//  updating_pill_detail_test.dart — La pastille « Mise à jour… » dit
//  où en est l'import, en chiffres seulement (rien à traduire).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart';

void main() {
  test('hors import ou sans chiffre : rien', () {
    expect(updatingPillDetail(null), '');
    expect(updatingPillDetail(const ImportProgress(ImportStage.connecting)), '');
    expect(updatingPillDetail(const ImportProgress(ImportStage.categories)), '');
    expect(updatingPillDetail(const ImportProgress(ImportStage.downloading)), '');
    expect(updatingPillDetail(const ImportProgress(ImportStage.saving)), '');
  });

  test('téléchargement : mégaoctets reçus', () {
    expect(
      updatingPillDetail(
        const ImportProgress(ImportStage.downloading, bytes: 13002342),
      ),
      '12.4 Mo',
    );
    expect(
      updatingPillDetail(
        const ImportProgress(ImportStage.decoding, bytes: 1048576),
      ),
      '1.0 Mo',
    );
  });

  test('chaînes trouvées puis enregistrées, lisibles à 3 m', () {
    expect(
      updatingPillDetail(const ImportProgress(ImportStage.found, count: 18230)),
      '18 230',
    );
    expect(
      updatingPillDetail(
        const ImportProgress(ImportStage.saving, index: 12000, total: 18230),
      ),
      '12 000 / 18 230',
    );
    expect(
      updatingPillDetail(
        const ImportProgress(ImportStage.category, index: 3, total: 40, count: 900),
      ),
      '3 / 40',
    );
    expect(
      updatingPillDetail(const ImportProgress(ImportStage.done, count: 18230)),
      '18 230',
    );
  });
}
