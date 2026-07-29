// =========================================================
//  remote_source_repository_dedup_test.dart — Dédup in-flight de sync()
// =========================================================
//  `RemoteSourceRepository.sync()` est appelé par PLUSIEURS boucles
//  concurrentes (timer 5 min, sondage d'activation 6-8 s, WebSocket,
//  boot). Sans verrou, deux appels simultanés lançaient DEUX imports de
//  la même source (double pic mémoire, doublons possibles).
//
//  Le corps réel (`_doSync`) touche le réseau : on le remplace par le
//  seam `debugSyncBody` (pur, piloté par un Completer) pour vérifier la
//  seule chose qui compte ici — la dédup :
//    • tant qu'une passe est en cours, tout appel reçoit le MÊME Future
//      (le corps n'est exécuté qu'UNE fois) ;
//    • une fois la passe terminée, un nouvel appel relance une passe.
// =========================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

void main() {
  tearDown(() {
    // On ne laisse jamais le seam posé pour les autres tests.
    RemoteSourceRepository.debugSyncBody = null;
  });

  test('deux sync() simultanés partagent la MÊME passe (corps exécuté 1 fois)',
      () async {
    int calls = 0;
    Completer<RemoteSyncResult> gate = Completer<RemoteSyncResult>();
    RemoteSourceRepository.debugSyncBody = () {
      calls++;
      return gate.future;
    };

    // 1) Deux appels pendant que la passe est en vol → même Future, un
    //    seul démarrage du corps.
    final Future<RemoteSyncResult> a = RemoteSourceRepository.sync();
    final Future<RemoteSyncResult> b = RemoteSourceRepository.sync();
    expect(identical(a, b), isTrue,
        reason: 'un appel concurrent doit rejoindre la passe en cours');
    expect(calls, 1, reason: 'le corps ne doit tourner qu\'une seule fois');

    // 2) Les deux appelants reçoivent le même résultat.
    gate.complete(RemoteSyncResult.loaded);
    expect(await a, RemoteSyncResult.loaded);
    expect(await b, RemoteSyncResult.loaded);

    // 3) Passe terminée → un NOUVEL appel relance bien une passe.
    gate = Completer<RemoteSyncResult>();
    final Future<RemoteSyncResult> c = RemoteSourceRepository.sync();
    expect(identical(a, c), isFalse,
        reason: 'après la fin d\'une passe, sync() doit repartir de zéro');
    expect(calls, 2);
    gate.complete(RemoteSyncResult.noSource);
    expect(await c, RemoteSyncResult.noSource);
  });

  test('la dédup se libère AUSSI quand la passe échoue', () async {
    int calls = 0;
    RemoteSourceRepository.debugSyncBody = () {
      calls++;
      return Future<RemoteSyncResult>.error(StateError('boom'));
    };

    await expectLater(
        RemoteSourceRepository.sync(), throwsA(isA<StateError>()));

    // L'échec ne doit pas laisser un Future zombie en vol : l'appel
    // suivant relance une vraie passe.
    RemoteSourceRepository.debugSyncBody = () {
      calls++;
      return Future<RemoteSyncResult>.value(RemoteSyncResult.loaded);
    };
    expect(await RemoteSourceRepository.sync(), RemoteSyncResult.loaded);
    expect(calls, 2);
  });
}
