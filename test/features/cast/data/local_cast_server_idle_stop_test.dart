// =========================================================
//  local_cast_server_idle_stop_test.dart — Fermeture sur inactivité
// =========================================================
//  Résiduel AUDIT-DURCISSEMENT-TV §5 : `LocalCastServer.stop()` n'était
//  JAMAIS appelé — la socket d'écoute LAN restait ouverte à vie après
//  le dernier cast. Le correctif arme une grâce quand la dernière
//  session (relais DLNA/HLS ou navigateur) est libérée, et l'annule
//  dès qu'une session (re)naît — un zap rapide ne fait pas churner le
//  bind, mais un cast terminé finit socket FERMÉE.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

void main() {
  // PAS de TestWidgetsFlutterBinding ici : il remplacerait HttpClient
  // par un mock — or ces tests exercent de VRAIES sockets loopback
  // (même approche que relay_upstream_reconnect_test).

  const DlnaProfile profile = DlnaProfile(
    mime: 'video/mp2t',
    profileName: 'MPEG_TS_SD_NA_ISO',
    transferMode: DlnaTransferMode.streaming,
    objectClass: 'object.item.videoItem.videoBroadcast',
    fileExtension: 'ts',
  );

  setUp(() {
    LocalCastServer.idleStopGrace = const Duration(milliseconds: 80);
  });

  tearDown(() async {
    await LocalCastServer.instance.stop();
    LocalCastServer.idleStopGrace = const Duration(minutes: 2);
  });

  Future<String> register(LocalCastServer server) async {
    final String? url = await server.registerRelay(
      upstreamUrl: 'http://127.0.0.1:9/live.ts',
      profile: profile,
      receiverHost: '127.0.0.1',
    );
    expect(url, isNotNull);
    return url!;
  }

  test('dernière session libérée → la socket LAN se ferme après la grâce',
      () async {
    final LocalCastServer server = LocalCastServer.instance;
    final String url = await register(server);
    expect(server.isRunning, isTrue);

    server.clearRelay(url);
    // Pendant la grâce, le serveur tourne encore (un zap doit pouvoir
    // réutiliser le bind sans re-payer un start()).
    expect(server.isRunning, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.isRunning, isFalse);
  });

  test('une session navigateur active empêche la fermeture', () async {
    final LocalCastServer server = LocalCastServer.instance;
    final String relay = await register(server);
    // serveBrowser enregistre la session AVANT la découverte d'IP :
    // même si celle-ci échouait, la session navigateur serait active.
    await server.serveBrowser(upstreamUrl: 'http://127.0.0.1:9/scr.ts');

    server.clearRelay(relay);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Le navigateur regarde encore : on ne coupe pas sous ses pieds.
    expect(server.isRunning, isTrue);

    server.stopBrowser();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.isRunning, isFalse);
  });

  test('un nouveau cast pendant la grâce annule la fermeture (zap)',
      () async {
    final LocalCastServer server = LocalCastServer.instance;
    final String a = await register(server);
    final int portBefore = server.port;

    server.clearRelay(a);
    // Zap : nouvelle chaîne enregistrée AVANT l'expiration de la grâce.
    final String b = await register(server);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.isRunning, isTrue);
    // Même bind réutilisé — l'URL du zap reste servie par le même port.
    expect(server.port, portBefore);
    expect(Uri.parse(b).port, portBefore);

    server.clearRelay(b);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.isRunning, isFalse);
  });
}
