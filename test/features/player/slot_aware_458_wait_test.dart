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
        // Occupé aux 3 premiers sondages (1,1 s / 2 s / 3 s), libéré ensuite.
        probe: () async => ++probes <= 3,
        reopens: reopens,
        verdicts: verdicts,
      );

      expect(fallback.onContainerUnsupported(), isTrue,
          reason: 'sans frame décodée, le 3003 doit partir en attente 458');

      // Paliers 1-3 (1,1 + 2 + 3 s) : occupé → pas de réouverture.
      fake.elapse(const Duration(milliseconds: 6200));
      expect(reopens, isEmpty,
          reason: 'créneau occupé = ne pas brûler de connexion refusée');

      // Palier 4 (5 s) : le sondage dit LIBÉRÉ → réouverture immédiate.
      fake.elapse(const Duration(seconds: 5));
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
      // Tout le calendrier progressif (~150 s) + une partie de la patrouille.
      fake.elapse(const Duration(seconds: 200));
      expect(reopens, isEmpty,
          reason: 'occupé du début à la fin = aucune réouverture brûlée');
      expect(verdicts, isEmpty,
          reason: 'décision du 21/08 : plus JAMAIS l\'écran « limite de '
              'connexions » — la patrouille continue en silence');

      // Libération tardive → la cadence de garde (30 s) rouvre toute seule.
      freed = true;
      fake.elapse(const Duration(seconds: 31));
      expect(reopens, <String>[channel.streamUrl]);
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
}
