// =========================================================
//  relay_timeshift_test.dart — Pause du direct (différé) via le relais
// =========================================================
//  Garanties vérifiées :
//    1. startTimeshift ne rouvre PAS de connexion amont (tee sur la
//       session du lecteur) ;
//    2. la route /shift rejoue le tampon DEPUIS SON DÉBUT puis suit sa
//       croissance (les octets reçus par le client différé dépassent la
//       taille du tampon au moment de la connexion) ;
//    3. stopTimeshift ferme la route (fin de flux) et supprime le fichier.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  late HttpServer fakeUpstream;
  late String fakeUrl;
  int upstreamConnections = 0;
  Timer? feeder;

  setUp(() async {
    upstreamConnections = 0;
    fakeUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fakeUrl = 'http://127.0.0.1:${fakeUpstream.port}/live-shift';
    fakeUpstream.listen((HttpRequest req) {
      upstreamConnections++;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.bufferOutput = false;
      final List<int> packet = List<int>.filled(188, 0x47);
      feeder?.cancel();
      feeder = Timer.periodic(const Duration(milliseconds: 10), (_) {
        try {
          req.response.add(packet);
        } catch (_) {}
      });
    });
  });

  tearDown(() async {
    feeder?.cancel();
    await LocalStreamRelay.instance.closeOtherPlaybacks('');
    await fakeUpstream.close(force: true);
  });

  test('pause = tampon sur la même connexion ; reprise = rejoue depuis le début',
      () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.playUrlFor(fakeUrl);

    // Le « lecteur » lit le direct.
    final HttpClient live = HttpClient();
    final HttpClientResponse liveResp =
        await (await live.getUrl(Uri.parse(localUrl))).close();
    int liveBytes = 0;
    final StreamSubscription<List<int>> liveSub =
        liveResp.listen((List<int> c) => liveBytes += c.length);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(liveBytes, greaterThan(0));

    // PAUSE : ouverture du tampon.
    expect(await relay.startTimeshift(fakeUrl), isTrue);
    expect(relay.isTimeshifting(fakeUrl), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final int bufferedAtResume = relay.timeshiftBytes(fakeUrl);
    expect(bufferedAtResume, greaterThan(0), reason: 'le tampon se remplit');

    // Le lecteur lâche le direct (comme ExoPlayer quand on change d'URL).
    await liveSub.cancel();
    live.close(force: true);

    // REPRISE : lecture du tampon depuis l'octet 0.
    final HttpClient shifted = HttpClient();
    final HttpClientResponse shiftResp = await (await shifted
            .getUrl(Uri.parse(relay.timeshiftPlayUrl(fakeUrl))))
        .close();
    expect(shiftResp.statusCode, 200);
    expect(shiftResp.headers.contentType?.mimeType, 'video/mp2t');
    int shiftBytes = 0;
    final Completer<void> ended = Completer<void>();
    shiftResp.listen((List<int> c) => shiftBytes += c.length,
        onDone: ended.complete, onError: (Object _) => ended.complete());
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(shiftBytes, greaterThan(bufferedAtResume),
        reason: 'on relit le début PUIS on suit la croissance du tampon');

    // UNE seule connexion amont pour tout ça.
    expect(upstreamConnections, 1);

    // RETOUR AU DIRECT : le tampon se ferme (fin de flux) et disparaît.
    await relay.stopTimeshift(fakeUrl);
    await ended.future.timeout(const Duration(seconds: 3));
    expect(relay.isTimeshifting(fakeUrl), isFalse);
    shifted.close(force: true);
    final Directory dir = Directory('${Directory.systemTemp.path}/timeshift');
    if (await dir.exists()) {
      final List<FileSystemEntity> leftovers = dir
          .listSync()
          .where((FileSystemEntity f) =>
              f.path.contains('shift-${fakeUrl.hashCode & 0x7fffffff}-'))
          .toList();
      expect(leftovers, isEmpty, reason: 'le fichier tampon est supprimé');
    }
  });

  test('/shift sans session → 404', () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    await relay.playUrlFor(fakeUrl); // démarre le serveur local
    final HttpClient c = HttpClient();
    final HttpClientResponse r = await (await c.getUrl(
            Uri.parse(relay.timeshiftPlayUrl('http://nowhere/none.ts'))))
        .close();
    expect(r.statusCode, 404);
    c.close(force: true);
  });
}
