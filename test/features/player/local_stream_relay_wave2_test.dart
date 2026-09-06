// =========================================================
//  local_stream_relay_wave2_test.dart — Vague 2 : « la ligne unique »
// =========================================================
//  Audit externe (05/09/2026), points 2.3 / 2.4 / 2.5 : trois fuites de
//  connexion dans le relais, toutes du même genre — une session qui
//  survit, ou qui en tue une autre, parce qu'un `await` a laissé passer
//  du temps. Chaque test ci-dessous REJOUE la fuite avec un vrai serveur
//  HTTP local et vérifie qu'elle ne se produit plus.
//
//  Ce fichier utilise de vraies sockets et de vrais délais : le back-off
//  du relais est de 2 s (+ jitter), on ne peut pas le simuler sans
//  réécrire le relais. Compter ~12 s au total.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

/// Journal boîte noire aplati.
String _journal() => StreamDiagnostics.instance.events
    .map((StreamDiagEvent e) => e.message)
    .join('\n');

/// Un serveur qui débite du TS sur chaque requête, et compte ses hits.
/// [firstRequest] permet de faire autre chose sur la 1re connexion.
class _TsServer {
  _TsServer(this.server, this.port);
  final HttpServer server;
  final int port;
  final List<Timer> feeds = <Timer>[];
  int hits = 0;

  static Future<_TsServer> start({
    Future<void> Function(HttpRequest req)? firstRequest,
    ContentType? mime,
  }) async {
    final HttpServer srv =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final _TsServer s = _TsServer(srv, srv.port);
    srv.listen((HttpRequest req) async {
      s.hits++;
      if (s.hits == 1 && firstRequest != null) {
        await firstRequest(req);
        return;
      }
      req.response.statusCode = 200;
      req.response.headers.contentType = mime ?? ContentType('video', 'mp2t');
      req.response.bufferOutput = false;
      final List<int> packet = List<int>.filled(188, 0x47);
      s.feeds.add(Timer.periodic(const Duration(milliseconds: 20), (_) {
        try {
          req.response.add(packet);
        } catch (_) {}
      }));
    });
    return s;
  }

  String url(String path) => 'http://127.0.0.1:$port$path';

  Future<void> close() async {
    for (final Timer t in feeds) {
      t.cancel();
    }
    await server.close(force: true);
  }
}

/// Branche un « lecteur » sur l'URL locale et compte les octets reçus.
class _Player {
  _Player(this.client, this.sub, this.closed);
  final HttpClient client;
  final StreamSubscription<List<int>> sub;
  final Completer<void> closed;
  int bytes = 0;

  static Future<_Player> connect(String localUrl) async {
    final HttpClient client = HttpClient();
    final HttpClientResponse resp =
        await (await client.getUrl(Uri.parse(localUrl))).close();
    final Completer<void> closed = Completer<void>();
    late _Player p;
    final StreamSubscription<List<int>> sub = resp.listen(
      (List<int> c) => p.bytes += c.length,
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
      onError: (Object _) {
        if (!closed.isCompleted) closed.complete();
      },
    );
    p = _Player(client, sub, closed);
    return p;
  }

  Future<void> stop() async {
    await sub.cancel();
    client.close(force: true);
  }
}

void main() {
  final LocalStreamRelay relay = LocalStreamRelay.instance;

  // ---------------------------------------------------------------
  //  2.5 — un 200 qui n'est pas un flux
  // ---------------------------------------------------------------
  group('2.5 — HTTP 200 mais une PAGE, pas un flux', () {
    test('200 + text/html + taille connue (page « compte expiré ») → '
        'fermeture définitive, AUCUNE reconnexion', () async {
      const String page = '<html><body>Account expired</body></html>';
      final _TsServer srv = await _TsServer.start(
        firstRequest: (HttpRequest req) async {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.html;
          req.response.contentLength = page.length;
          req.response.write(page);
          await req.response.close();
        },
      );
      // Le serveur ne sert la page qu'à la 1re requête : si le relais
      // reconnectait, la 2e requête recevrait du TS et `hits` vaudrait 2.
      final String localUrl = await relay.playUrlFor(srv.url('/U/P/1.ts'));
      final _Player p = await _Player.connect(localUrl);
      await p.closed.future.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('le relais doit fermer la session (EOF)'));

      // Fenêtre où le back-off (2 s + jitter) aurait relancé.
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(srv.hits, 1,
          reason: 'une page HTML de 40 octets n\'est pas un flux : on ne '
              'reconnecte pas en boucle dessus');
      expect(_journal(), contains('page, pas un flux'));

      await p.stop();
      await srv.close();
    });

    test('200 + text/html SANS taille connue (PHP mal configuré) → le flux '
        'passe quand même', () async {
      // Un serveur PHP qui diffuse un .ts sans poser d'en-tête envoie
      // `text/html` par défaut, en chunked. Juger sur le MIME seul aurait
      // coupé ce client-là. On vérifie que les octets arrivent.
      final _TsServer srv = await _TsServer.start(mime: ContentType.html);
      // Le journal est GLOBAL et cumulatif : on ne compte que ce qui
      // s'y ajoute pendant ce test.
      final int avant = 'page, pas un flux'.allMatches(_journal()).length;
      final String localUrl = await relay.playUrlFor(srv.url('/U/P/2.ts'));
      final _Player p = await _Player.connect(localUrl);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(p.bytes, greaterThan(0),
          reason: 'text/html sans Content-Length peut être un vrai flux');
      expect('page, pas un flux'.allMatches(_journal()).length, avant,
          reason: 'aucun refus « page » ne doit être tracé pour ce flux');

      await p.stop();
      await srv.close();
    });
  });

  // ---------------------------------------------------------------
  //  2.4 — le réveil tardif d'une session fermée ne tue pas sa remplaçante
  // ---------------------------------------------------------------
  test('2.4 — session A fermée pendant son back-off : son réveil tardif '
      'ne décroche PAS la session B ouverte sur la même chaîne', () async {
    final _TsServer srv = await _TsServer.start(
      firstRequest: (HttpRequest req) async {
        // Vraie panne réseau : socket coupée SANS en-têtes.
        final Socket s = await req.response.detachSocket(writeHeaders: false);
        s.destroy();
      },
    );
    final String real = srv.url('/U/P/3.ts');

    // A : 1re connexion coupée → A part en back-off (≥ 2 s).
    //
    // ATTENTION au piège (mesuré le 06/09) : le relais n'envoie les
    // en-têtes au lecteur qu'au premier octet amont. Attendre la réponse
    // ici bloquerait jusqu'à la reconnexion d'A (2 s+) — et A ne serait
    // plus « en back-off » au moment de la fermer. On envoie donc la
    // requête SANS attendre sa réponse.
    final String localUrl = await relay.playUrlFor(real);
    final HttpClient clientA = HttpClient();
    final Future<HttpClientResponse> pendingA =
        clientA.getUrl(Uri.parse(localUrl)).then(
            (HttpClientRequest r) => r.close());
    unawaited(pendingA.then((HttpClientResponse r) => r.drain<void>(),
        onError: (Object _) {}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(srv.hits, 1, reason: 'A est en back-off, pas encore reconnectée');

    // L'écran quitte : A est fermée (mais sa reconnexion différée dort).
    await relay.closeOtherPlaybacks('');
    clientA.close(force: true);

    // Le client revient sur la MÊME chaîne — comme le ferait l'écran
    // suivant : `playUrlFor` redéclare la lecture (sans lui, le serveur
    // local refuse d'ouvrir un amont : garde-fou anti-zap), puis le
    // lecteur se branche → session B, qui diffuse.
    final String localUrlB = await relay.playUrlFor(real);
    final _Player pB = await _Player.connect(localUrlB);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(pB.bytes, greaterThan(0), reason: 'B doit diffuser');
    expect(relay.activeUpstreamCount, 1);

    // A se réveille (2 s + jitter < 1 s) et se ferme « pour de bon ».
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    // AVANT le correctif : A retirait l'entrée PAR URL → B disparaissait
    // du registre : activeUpstreamCount tombait à 0 alors que B diffusait
    // toujours — invisible, infermable, une 2e connexion au prochain zap.
    expect(relay.activeUpstreamCount, 1,
        reason: 'B doit rester dans le registre après le réveil tardif d\'A');
    final int before = pB.bytes;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(pB.bytes, greaterThan(before), reason: 'B diffuse toujours');

    await relay.closeOtherPlaybacks('');
    await pB.stop();
    await srv.close();
  });

  // ---------------------------------------------------------------
  //  2.3 — la fermeture tardive d'un écran ne touche pas l'écran suivant
  // ---------------------------------------------------------------
  test('2.3 — closeOtherPlaybacks(upToGeneration) épargne la session née '
      'après le début de la fermeture', () async {
    final _TsServer srv = await _TsServer.start();
    final String urlA = srv.url('/U/P/france2.ts');
    final String urlB = srv.url('/U/P/france3.ts');

    // Écran 1 joue A.
    final String localA = await relay.playUrlFor(urlA);
    final _Player pA = await _Player.connect(localA);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(pA.bytes, greaterThan(0));

    // Écran 1 COMMENCE sa fermeture : il note le rang courant…
    final int gen = relay.sessionGeneration;

    // …mais ses `await` (stop natif) laissent l'écran 2 ouvrir B.
    final String localB = await relay.playUrlFor(urlB);
    final _Player pB = await _Player.connect(localB);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(pB.bytes, greaterThan(0));

    // Écran 1 se réveille et ferme « tout sauf rien » — borné à son rang.
    await relay.closeOtherPlaybacks('', upToGeneration: gen);
    final int before = pB.bytes;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // AVANT : B était fermée ici — « le client venait de lancer une chaîne
    // et elle se coupait sous ses yeux ».
    expect(pB.bytes, greaterThan(before),
        reason: 'la session de l\'écran suivant ne doit pas être fermée');
    expect(pB.closed.isCompleted, isFalse);
    expect(relay.activeUpstreamCount, 1);

    await relay.closeOtherPlaybacks('');
    await pA.stop();
    await pB.stop();
    await srv.close();
  });
}
