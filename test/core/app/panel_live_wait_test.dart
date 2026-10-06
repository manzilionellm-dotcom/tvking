// =========================================================
//  panel_live_wait_test.dart — le panel joint le téléphone à l'instant
// =========================================================
//  Vrai PanelLiveWait, serveur simulé (MockClient) qui imite
//  GET /api/box/wait du Worker : la requête reste ouverte puis répond
//  quand un ordre part. Aucune adresse réelle, aucun secret.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/panel_live_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('règle pure', () {
    test('un ordre nouveau → relire, curseur avancé', () {
      final LiveWaitStep s = readLiveWait(<String, Object>{
        'box': <Map<String, Object>>[
          <String, Object>{'id': 7, 'kind': 'source_clear'},
          <String, Object>{'id': 9, 'kind': 'source'},
        ],
      }, 5);
      expect(s.changed, isTrue);
      expect(s.cursor, 9);
    });

    test('délai écoulé sans ordre, ordre déjà vu, corps illisible : rien', () {
      expect(readLiveWait(<String, Object>{'timeout': true, 'box': <Object>[]}, 4).changed, isFalse);
      final LiveWaitStep old = readLiveWait(<String, Object>{
        'box': <Map<String, Object>>[<String, Object>{'id': 3}],
      }, 4);
      expect(old.changed, isFalse);
      expect(old.cursor, 4, reason: 'le curseur ne recule jamais');
      expect(readLiveWait('pas du json', 4).changed, isFalse);
    });

    test('réessai : 2, 4, 8, 16, 30 s au plus', () {
      expect(liveWaitBackoff(0), Duration.zero);
      expect(liveWaitBackoff(1), const Duration(seconds: 2));
      expect(liveWaitBackoff(3), const Duration(seconds: 8));
      expect(liveWaitBackoff(9), const Duration(seconds: 30));
    });
  });

  group('boucle réelle', () {
    late PanelLiveWait w;
    late int syncs;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'device.virtual_mac.v1': 'MK:30:70:0E:D7:5B',
      });
      w = PanelLiveWait.instance;
      w.stop();
      syncs = 0;
      w.onChange = () async => syncs++;
    });

    tearDown(() => w.stop());

    test('« Effacer les listes » au panel → relecture immédiate, pas au bout de 60 s', () async {
      final Completer<void> panelClick = Completer<void>();
      int calls = 0;
      final List<String> afters = <String>[];
      w.clientFactory = () => MockClient((http.Request r) async {
            expect(r.url.path, '/api/box/wait/MK:30:70:0E:D7:5B');
            afters.add(r.url.queryParameters['after'] ?? '');
            calls++;
            if (calls == 1) {
              // Le serveur garde la requête ouverte jusqu'au clic du panel.
              await panelClick.future;
              return http.Response(jsonEncode(<String, Object>{
                'box': <Map<String, Object>>[<String, Object>{'id': 12, 'kind': 'source_clear'}],
              }), 200);
            }
            // Ensuite : attente sans ordre.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return http.Response(jsonEncode(<String, Object>{'timeout': true, 'box': <Object>[]}), 200);
          });
      w.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(syncs, 0, reason: 'rien tant que le panel n’a rien envoyé');

      final Stopwatch sw = Stopwatch()..start();
      panelClick.complete();
      while (syncs == 0 && sw.elapsedMilliseconds < 2000) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(syncs, 1);
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'à l’instant, pas au tour de 60 s');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(afters.skip(1).every((String a) => a == '12'), isTrue,
          reason: 'l’ordre n’est pas retraité : curseur avancé à 12');
      expect(syncs, 1);
      expect((await SharedPreferences.getInstance()).getInt(kLiveWaitCursorKey), 12);
    });

    test('serveur sans canal (404) : l’écoute s’arrête, pas de boucle', () async {
      int calls = 0;
      w.clientFactory = () => MockClient((http.Request r) async {
            calls++;
            return http.Response('{}', 404);
          });
      w.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 1);
      expect(syncs, 0);
    });

    test('ordres pendant une relecture : une seule relance, jamais deux en parallèle', () async {
      int inFlight = 0;
      int maxInFlight = 0;
      final Completer<void> slow = Completer<void>();
      w.onChange = () async {
        syncs++;
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        if (syncs == 1) await slow.future;
        inFlight--;
      };
      unawaited(w.trigger());
      unawaited(w.trigger());
      unawaited(w.trigger());
      slow.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(maxInFlight, 1);
      expect(syncs, 2, reason: 'la première + une relance pour les ordres arrivés pendant');
    });
  });
}
