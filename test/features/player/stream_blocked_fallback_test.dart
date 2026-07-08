// =========================================================
//  stream_blocked_fallback_test.dart — LE VRAI CHEMIN terrain
// =========================================================
//  3e itération du bug « la cascade ne s'exécute jamais » : ce test
//  reproduit le chemin de lecture RÉEL, avec les objets de PRODUCTION :
//
//    lecteur ouvre .ts → LocalStreamRelay (RÉEL, panel mocké 404)
//      → événement `definitiveFailures`
//      → StreamBlockedFallback (RÉEL — la classe que VideoPlayerScreen
//        instancie, abonnée par son propre attach(), pas une copie)
//      → sonde StreamProbe (RÉELLE, vraies requêtes HTTP)
//      → XtreamCascadeProber (RÉEL) → /live/….m3u8 en 200
//      → reopen() rappelé avec la variante → lecture via le relais.
//
//  Le widget lui-même (VideoPlayerScreen) n'apparaît pas : il embarque
//  libmpv, indisponible sous `flutter test`. Depuis la 3e itération il
//  ne contient plus AUCUNE logique — uniquement des liaisons d'état
//  (mounted, chaîne courante, setState) fournies ici à l'identique.
//
//  ASSERTIONS CONTRACTUELLES (mission 2026-07-08) :
//    - le journal contient « [cascade] DÉMARRAGE : N variante(s) » ;
//    - le journal contient au moins un « essai X/N … → statut » ;
//    - le lecteur est rouvert sur la variante gagnante et reçoit des
//      octets ;
//    - l'extrait de journal est IMPRIMÉ (livrable du rapport).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/stream_blocked_fallback.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

void main() {
  test(
      'VRAI CHEMIN : ouverture .ts → relais 404 → StreamBlockedFallback → '
      'cascade → /live/….m3u8 → lecture rouverte', () async {
    // ----- Panel Xtream mocké : 404 partout SAUF /live/USER/PASS/42.m3u8
    final List<Timer> feeds = <Timer>[];
    final HttpServer panel =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    panel.listen((HttpRequest req) async {
      if (req.uri.path == '/live/USER/PASS/42.m3u8') {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.bufferOutput = false;
        final List<int> packet = List<int>.filled(188, 0x47);
        feeds.add(Timer.periodic(const Duration(milliseconds: 20), (_) {
          try {
            req.response.add(packet);
          } catch (_) {}
        }));
        return;
      }
      req.response.statusCode = 404;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html>not found</html>');
      await req.response.close();
    });
    final String tsUrl = 'http://127.0.0.1:${panel.port}/USER/PASS/42.ts';

    // ----- Source Xtream en cache (le gate du diagnostic la vérifie) --
    PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[
      Playlist(
        id: 77,
        name: 'Panel test',
        type: PlaylistType.xtream,
        createdAt: 0,
        xtreamServer: 'http://127.0.0.1:${panel.port}',
        xtreamUsername: 'USER',
        xtreamPassword: 'PASS',
      ),
    ]);
    final Channel channel = Channel(
      id: 'chan-42',
      playlistId: 77,
      name: 'France 2 (test)',
      category: 'TNT',
      streamUrl: tsUrl,
      isLive: true,
    );

    // ----- Liaisons du widget (uniquement de l'ÉTAT, aucune logique) --
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    String? adoptedAltUrl;
    final List<String> blockedMessages = <String>[];
    final Completer<String> reopened = Completer<String>();
    String effectiveUrl() => adoptedAltUrl ?? channel.streamUrl;

    final StreamBlockedFallback fallback = StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: effectiveUrl,
      isAlive: () => true,
      hasDecodedFrames: () => false,
      getAdoptedAltUrl: () => adoptedAltUrl,
      setAdoptedAltUrl: (String? url) => adoptedAltUrl = url,
      resetWatchdogBudget: () {},
      reopen: (String url) {
        if (!reopened.isCompleted) reopened.complete(url);
      },
      showBlocked: blockedMessages.add,
    )..attach(); // le VRAI abonnement de production au relais

    // ----- 1) « _openMedia » : le lecteur ouvre la forme .ts ----------
    final String localTs = await relay.playUrlFor(tsUrl);
    final HttpClient client = HttpClient();
    final HttpClientResponse deadResp =
        await (await client.getUrl(Uri.parse(localTs))).close();
    await deadResp.drain<void>().timeout(const Duration(seconds: 5));

    // ----- 2) Le fallback de PROD doit rouvrir sur la variante --------
    final String winnerUrl = await reopened.future
        .timeout(const Duration(seconds: 15), onTimeout: () {
      fail('reopen() jamais appelé : la chaîne relais→fallback→cascade '
          'est cassée.\nJournal:\n${_journal()}');
    });
    expect(winnerUrl, endsWith('/live/USER/PASS/42.m3u8'));
    expect(adoptedAltUrl, winnerUrl,
        reason: 'la variante doit être adoptée pour les réouvertures');
    expect(blockedMessages, isEmpty,
        reason: 'pas d\'erreur montrée quand une variante gagne');

    // ----- 3) Lecture réelle via le relais sur la gagnante ------------
    final String localWinner = await relay.playUrlFor(winnerUrl);
    final HttpClientResponse liveResp =
        await (await client.getUrl(Uri.parse(localWinner))).close();
    int bytes = 0;
    final StreamSubscription<List<int>> reading =
        liveResp.listen((List<int> c) => bytes += c.length);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(bytes, greaterThan(0),
        reason: 'la lecture doit repartir sur la variante gagnante');

    // ----- 4) Contrats de journal (missions des 3e et 4e itérations) --
    final String journal = _journal();
    expect(journal, contains('frames décodées: 0 → décision: cascade'),
        reason: 'la décision doit être journalisée avec le drapeau');
    expect(journal, contains('[cascade] DÉMARRAGE : 3 variante(s)'),
        reason: 'log d\'entrée INCONDITIONNEL de la cascade');
    expect(journal, contains('[cascade] essai 2/4'),
        reason: 'chaque variante doit être numérotée avec son statut');
    expect(journal, contains('→ OK'),
        reason: 'la variante gagnante doit afficher son verdict');
    expect(journal, isNot(contains('USER/PASS')),
        reason: 'identifiants toujours masqués dans le journal');

    // ----- LIVRABLE : extrait du journal (à coller dans le rapport) ---
    // ignore: avoid_print
    print('===== EXTRAIT JOURNAL (test chemin réel) =====');
    for (final StreamDiagEvent e in
        StreamDiagnostics.instance.events.toList().reversed) {
      // ignore: avoid_print
      print(e.toString());
    }
    // ignore: avoid_print
    print('===== FIN EXTRAIT =====');

    fallback.detach();
    await reading.cancel();
    client.close(force: true);
    for (final Timer t in feeds) {
      t.cancel();
    }
    await panel.close(force: true);
  });

  test('anti-boucle : 2e échec sur la MÊME chaîne → garde JOURNALISÉE '
      '+ erreur affichée (plus de sortie muette)', () async {
    final HttpServer dead =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dead.listen((HttpRequest req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    final String tsUrl = 'http://127.0.0.1:${dead.port}/USER/PASS/9.ts';
    PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);
    final Channel channel = Channel(
      id: 'chan-9',
      name: 'Morte',
      category: 'x',
      streamUrl: tsUrl,
      isLive: true,
    );
    final List<String> blockedMessages = <String>[];
    final StreamBlockedFallback fallback = StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => tsUrl,
      isAlive: () => true,
      hasDecodedFrames: () => false,
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (_) {},
      resetWatchdogBudget: () {},
      reopen: (_) {},
      showBlocked: blockedMessages.add,
    );

    await fallback.run(); // 1er diagnostic complet (échec total)
    expect(blockedMessages, hasLength(1));
    await fallback.run(); // 2e appel : garde anti-boucle
    expect(blockedMessages, hasLength(2),
        reason: 'la garde doit toujours montrer l\'erreur');
    expect(_journal(), contains('Diagnostic déjà TENTÉ'),
        reason: 'la garde anti-boucle ne doit plus être muette');

    await dead.close(force: true);
  });

  test('frames ≥1 (la chaîne DÉCODAIT) + échec relais → erreur directe '
      '« coupure réseau », PAS de cascade', () async {
    final HttpServer dead =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dead.listen((HttpRequest req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    final String tsUrl = 'http://127.0.0.1:${dead.port}/USER/PASS/5.ts';
    PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);
    final Channel channel = Channel(
      id: 'chan-5',
      name: 'Jouait avant',
      category: 'x',
      streamUrl: tsUrl,
      isLive: true,
    );
    final List<String> blockedMessages = <String>[];
    bool cascadeReopened = false;
    final StreamBlockedFallback fallback = StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => tsUrl,
      isAlive: () => true,
      hasDecodedFrames: () => true, // ≥1 frame décodée dans CETTE session
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (_) {},
      resetWatchdogBudget: () {},
      reopen: (_) => cascadeReopened = true,
      showBlocked: blockedMessages.add,
    )..attach();

    // « _openMedia » sur la .ts → 404 définitif → événement relais.
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localTs = await relay.playUrlFor(tsUrl);
    final HttpClient client = HttpClient();
    final HttpClientResponse resp =
        await (await client.getUrl(Uri.parse(localTs))).close();
    await resp.drain<void>().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(blockedMessages, isNotEmpty,
        reason: 'coupure sur une chaîne qui décodait → erreur directe');
    expect(blockedMessages.first, contains('Flux interrompu'));
    expect(cascadeReopened, isFalse,
        reason: 'pas de cascade quand la lecture avait réellement démarré');
    expect(_journal(),
        contains('frames décodées: ≥1 → décision: erreur directe'),
        reason: 'la décision doit être journalisée avec le drapeau');

    fallback.detach();
    client.close(force: true);
    await dead.close(force: true);
  });
}

String _journal() => StreamDiagnostics.instance.events
    .map((StreamDiagEvent e) => e.message)
    .join('\n');
