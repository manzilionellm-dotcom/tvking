// =========================================================
//  remote_source_store_default_test.dart — l'activation à distance,
//  PARTOUT, Play Store compris (décision du propriétaire, 20/09/2026)
// =========================================================
//  « L'essentiel, c'est d'activer à distance. Beaucoup de clients ne
//  savent pas faire. » Dit deux fois, après avoir été prévenu du risque
//  magasin. La source poussée par le panel doit donc être chargée dans
//  TOUS les builds — le build Play ne fait plus exception.
//
//  Ce test verrouille le DÉFAUT du champ, pas le mécanisme (que
//  remote_source_store_gate_test.dart couvre en le basculant à la main).
//  Si un patch futur remet `kIsPlayBuild` ici, c'est une décision du
//  propriétaire à obtenir de nouveau — et ce test le rappelle.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

void main() {
  test('la source poussée par le panel est chargée dans TOUS les builds', () {
    expect(RemoteSourceRepository.storeBuild, isFalse,
        reason: 'décision du propriétaire (20/09/2026) : l\'activation à '
            'distance est le cœur du produit, Play Store compris');
  });
}
