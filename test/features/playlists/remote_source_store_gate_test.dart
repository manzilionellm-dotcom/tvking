// =========================================================
//  remote_source_store_gate_test.dart — builds store = lecteur BYO
// =========================================================
//  Refus Amazon du 19/08/2026 (« pirated content ») : le testeur du store
//  voyait le bouquet poussé par le panel sur le compte de test. Règle
//  gravée ici : dans un build STORE (PLAY_BUILD=true), AUCUNE source n'est
//  poussée — ni au boot (sync), ni via l'écran d'activation
//  (fetchAssignedSources), ni par un événement temps réel (applySources).
//  L'utilisateur ajoute ses propres sources, point.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

void main() {
  tearDown(() => RemoteSourceRepository.storeBuild = false);

  test('build store : sync() ne pousse rien (pas même un appel réseau)',
      () async {
    RemoteSourceRepository.storeBuild = true;
    // Sans la garde, sync() partirait lire la MAC puis taper le backend —
    // en environnement de test, ça échouerait bruyamment. Le retour
    // immédiat « noSource » prouve que la porte est fermée AVANT tout I/O.
    expect(await RemoteSourceRepository.sync(), RemoteSyncResult.noSource);
  });

  test('build store : fetchAssignedSources() est toujours vide', () async {
    RemoteSourceRepository.storeBuild = true;
    expect(await RemoteSourceRepository.fetchAssignedSources(), isEmpty);
  });

  test('build store : applySources() ignore même une source déjà récupérée',
      () async {
    RemoteSourceRepository.storeBuild = true;
    final RemoteSyncResult r =
        await RemoteSourceRepository.applySources(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'xtream',
        'server_url': 'http://example.invalid:8080',
        'username': 'u',
        'password': 'p',
      },
    ]);
    expect(r, RemoteSyncResult.noSource,
        reason: 'un événement temps réel du panel ne doit rien charger '
            'dans un build store');
  });
}
