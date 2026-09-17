// =========================================================
//  tv_fatal_overlay_explainer_test.dart — l'overlay DIT le 502
// =========================================================
//  Terrain 17/09/2026 : Boîte noire = HTTP 502 (serveur fournisseur),
//  écran lecteur = « Chaîne indisponible pour le moment ». Le verdict
//  existait déjà (failure_explainer.dart). L'overlay l'ignorait.
//
//  Ce test lit le fichier RÉEL du lecteur TV. Si l'écran d'erreur
//  redevient un générique, ça casse ici.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('l\'overlay TV affiche le verdict, pas le générique', () {
    final File src =
        File('lib/features/tv/presentation/tv_player_screen.dart');
    expect(src.existsSync(), isTrue, reason: src.path);
    final String code = src.readAsStringSync();
    expect(code.contains('String? _fatalWhy'), isTrue);
    expect(code.contains('_fatalWhy = why.why'), isTrue);
    expect(
      code.contains('_fatalWhy ??'),
      isTrue,
      reason: 'l\'écran d\'erreur doit préférer le verdict explainer '
          'au l10n tvChannelUnavailable',
    );
  });
}
