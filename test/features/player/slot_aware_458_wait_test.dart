// =========================================================
//  slot_aware_458_wait_test.dart — attente MESURÉE du créneau
// =========================================================
//  Terrain 20/08 22:08 (« je ferme bien le cinéma, j'ouvre une chaîne →
//  Limite de connexions atteinte (1/1) ») : le calendrier 458 rouvrait
//  À L'AVEUGLE à chaque palier.
//
//  Décision propriétaire du 16/09 : « je ne veux jamais que ça se
//  redémarre ». 3 essais max (1,1 s + 2 s + 5 s), puis écran clair
//  « limite de connexions » + Réessayer manuel. PLUS de patrouille
//  infinie toutes les 30 s.
//
//  Contrat testé ici (sans réseau : sondage de créneau injecté) :
//    1. créneau occupé → AUCUNE réouverture brûlée ; libéré → réouverture
//       au palier suivant, pas à la fin du calendrier ;
//    2. créneau longtemps occupé → 1 réouverture de garantie (3e sondage
//       occupé), puis écran d'erreur, PLUS aucune relance auto ;
//    3. compteurs illisibles (source non-Xtream…) → comportement
//       historique : réouverture à l'aveugle à chaque palier (max 3).
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

  test('créneau longtemps occupé → 3 essais puis écran limite de '
      'connexions, pas de patrouille infinie', () {
    fakeAsync((FakeAsync fake) {
      final List<String> reopens = <String>[];
      final List<BlockedVerdict> verdicts = <BlockedVerdict>[];
      final StreamBlockedFallback fallback = build(
        probe: () async => true, // toujours occupé
        reopens: reopens,
        verdicts: verdicts,
      );

      expect(fallback.onContainerUnsupported(), isTrue);
      // 1,1 + 2 + 5 = 8,1 s. 3e sondage occupé → RÉOUVERTURE DE GARANTIE
      // (busySkips % 3 == 0). Pas encore d'écran : le calendrier n'est
      // épuisé qu'au 4e essai.
      fake.elapse(const Duration(seconds: 9));
      expect(reopens, hasLength(1),
          reason: '3 sondages occupés d\'affilée = une réouverture de '
              'garantie (le compteur du panel peut mentir)');
      expect(verdicts, isEmpty,
          reason: 'pas d\'écran tant que le calendrier n\'est pas épuisé');

      // 4e essai : calendrier (3 paliers) épuisé → verdict, plus de
      // réouverture automatique.
      expect(fallback.onContainerUnsupported(), isTrue);
      fake.flushMicrotasks();
      expect(verdicts, hasLength(1));
      expect(verdicts.single.kind, BlockedKind.maxConnections);
      expect(reopens, hasLength(1),
          reason: 'plus aucune réouverture automatique après 3 essais');

      // 60 s de plus : toujours rien (la patrouille 30 s n'existe plus).
      fake.elapse(const Duration(seconds: 60));
      expect(reopens, hasLength(1));
      expect(verdicts, hasLength(1));
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

      // Palier 3 (5 s) : encore une réouverture, puis budget épuisé.
      expect(fallback.onContainerUnsupported(), isTrue);
      fake.elapse(const Duration(seconds: 5));
      expect(reopens, hasLength(3));
      expect(verdicts, isEmpty);

      expect(fallback.onContainerUnsupported(), isTrue);
      fake.flushMicrotasks();
      expect(verdicts, hasLength(1));
      expect(verdicts.single.kind, BlockedKind.maxConnections);
      expect(reopens, hasLength(3),
          reason: '4e essai = écran, plus de réouverture auto');
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
