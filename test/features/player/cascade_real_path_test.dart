// =========================================================
//  cascade_real_path_test.dart — Cascade sur le CHEMIN DE LECTURE RÉEL
// =========================================================
//  Bug terrain du 2026-07-08 11:37 : le relais fermait bien la session
//  sur un 404 définitif… mais la cascade ne s'exécutait JAMAIS — le
//  déclencheur reposait sur la réaction de mpv à un flux vide, qui
//  n'arrive pas de façon fiable.
//
//  Ce test rejoue le VRAI enchaînement, composant par composant RÉEL :
//
//    lecteur ouvre .ts → LocalStreamRelay (vrai, upstream mocké 404)
//      → événement `definitiveFailures` (le canal EXPLICITE ajouté)
//      → XtreamCascadeProber.findWorkingVariant (LE code de prod que
//        VideoPlayerScreen appelle — pas une copie) avec la VRAIE
//        sonde réseau (StreamProbe)
//      → variante gagnante /live/….m3u8
//      → relais rouvert sur la gagnante → les octets coulent.
//
//  Seul le widget VideoPlayerScreen lui-même est absent : il embarque
//  libmpv (media_kit), indisponible dans l'environnement de test. Sa
//  glue (l'abonnement à `definitiveFailures` → _declareChannelBlocked)
//  est reproduite ici à l'identique ; tout le reste est le code réel.
//
//  On vérifie AUSSI le contrat de journal : chaque variante essayée
//  doit laisser une ligne « [cascade] essai i/N : … → statut » avec
//  identifiants MASQUÉS, alors que la sonde reçoit l'URL BRUTE.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/player_settings.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';
import 'package:tv_king/features/player/data/xtream_cascade_prober.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';

void main() {
  test(
      'player ouvre .ts → relais 404 → événement → cascade → '
      '/live/….m3u8 en 200 → la lecture redémarre', () async {
    // ----- Panel mocké : 404 partout SAUF /live/USER/PASS/42.m3u8 -----
    final List<Timer> feeds = <Timer>[];
    final List<String> upstreamPaths = <String>[];
    final HttpServer panel =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    panel.listen((HttpRequest req) async {
      upstreamPaths.add(req.uri.path);
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
    final String tsUrl =
        'http://127.0.0.1:${panel.port}/USER/PASS/42.ts';

    final LocalStreamRelay relay = LocalStreamRelay.instance;

    // ----- Glue du lecteur (identique à VideoPlayerScreen) -----
    //  Sur échec définitif de l'URL en cours : cascade via le code de
    //  prod, puis réouverture du relais sur la variante gagnante.
    final Completer<String> playbackRestarted = Completer<String>();
    final StreamSubscription<String> playerWiring =
        relay.definitiveFailures.listen((String failedUrl) async {
      if (failedUrl != tsUrl) return; // pas notre lecture en cours
      final CascadeWin? win = await XtreamCascadeProber.findWorkingVariant(
        tsUrl, // URL BRUTE, comme le fait _declareChannelBlocked
        XtreamContentType.live,
        uaCandidates: <String>[PlayerSettings.instance.userAgent],
      );
      if (win != null && !playbackRestarted.isCompleted) {
        // « _openMedia(win.url) » : réouverture via le relais.
        playbackRestarted.complete(await relay.playUrlFor(win.url));
      }
    });

    // ----- 1) Le lecteur ouvre la forme .ts via le relais -----
    final String localTs = await relay.playUrlFor(tsUrl);
    final HttpClient client = HttpClient();
    final HttpClientResponse deadResp =
        await (await client.getUrl(Uri.parse(localTs))).close();
    await deadResp.drain<void>().timeout(const Duration(seconds: 5));

    // ----- 2) Le relais signale, la cascade tourne, la lecture repart --
    final String localWinner = await playbackRestarted.future
        .timeout(const Duration(seconds: 10), onTimeout: () {
      fail('la cascade ne s\'est pas déclenchée après le 404 définitif');
    });
    final HttpClientResponse liveResp =
        await (await client.getUrl(Uri.parse(localWinner))).close();
    int bytes = 0;
    final StreamSubscription<List<int>> reading =
        liveResp.listen((List<int> c) => bytes += c.length);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(bytes, greaterThan(0),
        reason: 'la lecture doit repartir sur la variante gagnante');

    // ----- 3) Contrats vérifiés -----
    // Le panel a bien reçu l'URL BRUTE (identifiants réels, pas •••).
    expect(upstreamPaths, contains('/USER/PASS/42.ts'));
    expect(upstreamPaths, contains('/live/USER/PASS/42.m3u8'));
    // Le journal contient les essais numérotés avec statut, masqués.
    final String journal = StreamDiagnostics.instance.events
        .map((StreamDiagEvent e) => e.message)
        .join('\n');
    expect(journal, contains('[cascade] essai 2/4'));
    expect(journal, contains('→ OK'));
    expect(journal, isNot(contains('USER/PASS')),
        reason: 'les identifiants ne doivent JAMAIS fuiter dans le journal');

    await reading.cancel();
    await playerWiring.cancel();
    client.close(force: true);
    for (final Timer t in feeds) {
      t.cancel();
    }
    await panel.close(force: true);
  });

  test('gate non-Xtream : le prober trace « rien à essayer » sur une URL '
      'non réécrivable', () async {
    final CascadeWin? win = await XtreamCascadeProber.findWorkingVariant(
      'http://cdn.tv/stream.m3u8', // M3U générique : pas de schéma Xtream
      XtreamContentType.live,
      uaCandidates: const <String>['VLC/3.0.18 LibVLC/3.0.18'],
    );
    expect(win, isNull);
    final String journal = StreamDiagnostics.instance.events
        .map((StreamDiagEvent e) => e.message)
        .join('\n');
    expect(journal, contains('rien à essayer'));
  });
}
