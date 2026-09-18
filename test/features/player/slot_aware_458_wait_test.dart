// =========================================================
//  slot_aware_458_wait_test.dart — attente MESURÉE du créneau
// =========================================================
//  Terrain 20/08 22:08 (« je ferme bien le cinéma, j'ouvre une chaîne →
//  Limite de connexions atteinte (1/1) ») : le calendrier 458 de ~90 s
//  rouvrait À L'AVEUGLE à chaque palier et abandonnait sur un chiffre
//  rond — parfois juste avant que le panel ne libère la session du film
//  (son horloge démarre à la fermeture RÉELLE de la socket, jusqu'à
//  ~15 s après la sortie de l'écran, cf. mesure H1).
//
//  Et décision propriétaire du 21/08 (photo « Prime: 13eme RUE »,
//  « je veux plus voir ce message ») : l'écran « Limite de connexions
//  atteinte » ne doit PLUS JAMAIS s'afficher — la patrouille continue
//  sans fin et le flux redémarre seul à la libération.
//
//  Contrat testé ici (sans réseau : sondage de créneau injecté) :
//    1. créneau occupé → AUCUNE réouverture brûlée ; libéré → réouverture
//       au palier suivant, pas à la fin du calendrier ;
//    2. créneau longtemps occupé → AUCUN verdict, patrouille sans fin,
//       réouverture dès la libération même après ~150 s ;
//    3. compteurs illisibles (source non-Xtream…) → comportement
//       historique : réouverture à l'aveugle à chaque palier.
// =========================================================

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/data/stream_blocked_fallback.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

void main() {
  const Channel channel = Channel(
    id: 'chan-tf1',
    playlistId: 77,
    name: 'TF1 (test)',
    category: 'TNT',
    streamUrl: 'http://panel.example:8080/live/USER/PASS/1.ts',
    isLive: true,
  );

  StreamBlockedFallback build({
    required Future<bool?> Function() probe,
    required List<String> reopens,
    required List<BlockedVerdict> verdicts,
  }) {
    return StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => channel.streamUrl,
      isAlive: () => true,
      hasDecodedFrames: () => false,
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (String? _) {},
      resetWatchdogBudget: () {},
      reopen: reopens.add,
      showBlocked: verdicts.add,
      probeSlotBusy: probe,
    );
  }

  test('créneau occupé puis libéré → réouverture dès la libération, '
      'aucune connexion brûlée pendant l\'occupation', () {
    fakeAsync((FakeAsync fake) {
      final List<String> reopens = <String>[];
      final List<BlockedVerdict> verdicts = <BlockedVerdict>[];
      int probes = 0;
      final StreamBlockedFallback fallback = build(
        // Occupé au 1er sondage (1,1 s), libéré ensuite. (Au-delà de 2
        // sondages occupés d'affilée, la RÉOUVERTURE DE GARANTIE entre en
        // jeu — testée séparément ci-dessous.)
        probe: () async => ++probes <= 1,
        reopens: reopens,
        verdicts: verdicts,
      );

      expect(fallback.onContainerUnsupported(), isTrue,
          reason: 'sans frame décodée, le 3003 doit partir en attente 458');

      // Palier 1 (1,1 s) : occupé → pas de réouverture (attente mesurée).
      fake.elapse(const Duration(milliseconds: 1200));
      expect(reopens, isEmpty,
          reason: 'créneau occupé = ne pas brûler de connexion refusée');

      // Palier 2 (2 s) : le sondage dit LIBÉRÉ → réouverture immédiate.
      fake.elapse(const Duration(seconds: 2));
      expect(reopens, <String>[channel.streamUrl]);
      expect(verdicts, isEmpty,
          reason: 'aucune erreur montrée quand le créneau se libère');
    });
  });

  test('créneau longtemps occupé → AUCUN écran d\'erreur, patrouille sans '
      'fin, réouverture dès la libération (même après ~150 s)', () {
    fakeAsync((FakeAsync fake) {
      final List<String> reopens = <String>[];
      final List<BlockedVerdict> verdicts = <BlockedVerdict>[];
      bool freed = false;
      final StreamBlockedFallback fallback = build(
        probe: () async => !freed,
        reopens: reopens,
        verdicts: verdicts,
      );

      expect(fallback.onContainerUnsupported(), isTrue);
      // Paliers 1-2 (1,1 + 2 s) : occupé → sautés. 3e sondage occupé
      // (t ≈ 6,1 s) : RÉOUVERTURE DE GARANTIE (terrain 21/08 — des panels
      // figent/faussent active_cons ; sans elle, « logo qui tourne » sans
      // fin). Aucun écran d'erreur, toujours.
      fake.elapse(const Duration(seconds: 7));
      expect(reopens, hasLength(1),
          reason: '3 sondages occupés d\'affilée = une réouverture de '
              'garantie (le compteur du panel peut mentir)');
      expect(verdicts, isEmpty,
          reason: 'décision du 21/08 : plus JAMAIS l\'écran « limite de '
              'connexions » — la patrouille continue en silence');

      // La garantie a échoué (toujours occupé) → nouveau cycle : paliers
      // 4-5 (5 + 8 s) sautés, 6e sondage occupé (12 s) → garantie n° 2.
      expect(fallback.onContainerUnsupported(), isTrue);
      fake.elapse(const Duration(seconds: 26));
      expect(reopens, hasLength(2));
      expect(verdicts, isEmpty);

      // Libération tardive → le palier suivant (14 s) rouvre en mesuré.
      freed = true;
      expect(fallback.onContainerUnsupported(), isTrue);
      fake.elapse(const Duration(seconds: 15));
      expect(reopens, hasLength(3));
      expect(verdicts, isEmpty);
    });
  });

  test('compteurs illisibles → comportement historique (réouverture à '
      'l\'aveugle à chaque palier)', () {
    fakeAsync((FakeAsync fake) {
      final List<String> reopens = <String>[];
      final List<BlockedVerdict> verdicts = <BlockedVerdict>[];
      final StreamBlockedFallback fallback = build(
        probe: () async => null, // pas de source Xtream identifiable
        reopens: reopens,
        verdicts: verdicts,
      );

      expect(fallback.onContainerUnsupported(), isTrue);
      fake.elapse(const Duration(milliseconds: 1100));
      expect(reopens, hasLength(1),
          reason: 'sans compteurs, on garde la réouverture historique');

      // L'échec suivant reprogramme le palier 2 (2 s) — même mécanique.
      expect(fallback.onContainerUnsupported(), isTrue);
      fake.elapse(const Duration(seconds: 2));
      expect(reopens, hasLength(2));
      expect(verdicts, isEmpty);
    });
  });

  // ---------------------------------------------------------------
  //  Pré-attente AVANT la première ouverture (fluidité cinéma↔chaîne)
  // ---------------------------------------------------------------

  group('awaitProviderSlot (pré-attente mesurée avant ouverture)', () {
    XtreamAccountInfo counters({int? max, int? active}) =>
        XtreamAccountInfo(maxConnections: max, activeCons: active);

    test('créneau occupé puis libéré → rend la main dès la libération, '
        'sans jamais ouvrir de connexion refusée', () {
      fakeAsync((FakeAsync fake) {
        int probes = 0;
        bool done = false;
        StreamBlockedFallback.awaitProviderSlot(
          channel,
          probeOverride: () async {
            probes++;
            // Occupé aux 2 premiers sondages, libéré au 3e.
            return counters(max: 1, active: probes <= 2 ? 1 : 0);
          },
        ).then((_) => done = true);
        fake.elapse(const Duration(milliseconds: 100));
        expect(done, isFalse, reason: 'occupé → on attend');
        fake.elapse(const Duration(seconds: 4)); // 2 sondages à 1,6 s
        expect(done, isTrue);
        expect(probes, 3);
      });
    });

    test('jamais libéré → fail-open au budget (~10 s), l\'ouverture part '
        'quand même', () {
      fakeAsync((FakeAsync fake) {
        bool done = false;
        StreamBlockedFallback.awaitProviderSlot(
          channel,
          probeOverride: () async => counters(max: 1, active: 1),
        ).then((_) => done = true);
        fake.elapse(const Duration(seconds: 11));
        expect(done, isTrue,
            reason: 'la pré-attente ne bloque jamais une ouverture');
      });
    });

    test('compteurs illisibles → retour immédiat (comportement historique)',
        () {
      fakeAsync((FakeAsync fake) {
        bool done = false;
        StreamBlockedFallback.awaitProviderSlot(
          channel,
          probeOverride: () async => counters(max: null, active: null),
        ).then((_) => done = true);
        fake.flushMicrotasks();
        expect(done, isTrue);
      });
    });
  });
}
