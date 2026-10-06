// =========================================================
//  keep_old_lists_test.dart — Importer d'abord, effacer ensuite
// =========================================================
//  Avant le 06/10/2026 la box effaçait les listes que le panel ne servait
//  plus AVANT d'importer les nouvelles : un lien faux remplaçant un bon
//  laissait le client sans rien. Règle pure `keepOldLists`.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

void main() {
  test('nouvelle liste refusée alors que le panel retire l\'ancienne → on garde l\'ancienne', () {
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 1, servedCount: 1, anyLoaded: false, legacy: false),
      isTrue,
    );
  });

  test('nouvelle liste chargée → l\'ancienne part', () {
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 1, servedCount: 1, anyLoaded: true, legacy: false),
      isFalse,
    );
  });

  test('nouvelle liste mise de côté (délai de réessai, non essayée ce tour) → on garde l\'ancienne', () {
    // Bug corrigé le 06/10/2026 : « non essayée » valait « on efface ».
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 1, servedCount: 1, anyLoaded: false, legacy: false),
      isTrue,
    );
  });

  test('panel vidé (rien servi) → on efface, c\'est l\'intention', () {
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 2, servedCount: 0, anyLoaded: false, legacy: false),
      isFalse,
    );
  });

  test('rien retiré → rien à garder', () {
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 0, servedCount: 1, anyLoaded: false, legacy: false),
      isFalse,
    );
  });

  test('repli zuno.source.drop_first_legacy → ancien ordre, jamais gardée', () {
    expect(
      RemoteSourceRepository.keepOldLists(dropCount: 1, servedCount: 1, anyLoaded: false, legacy: true),
      isFalse,
    );
  });
}
