import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

void main() {
  final server = LocalCastServer.instance;
  late HttpClient client;

  Future<Map<String, dynamic>> current() async {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/current'));
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  setUp(() async {
    await server.stop();
    server.debugLanIpResolver = (_) async => '127.0.0.1';
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    server.debugLanIpResolver = null;
  });

  test('deux démarrages simultanés partagent un seul socket serveur', () async {
    final ports =
        await Future.wait(<Future<int>>[server.start(), server.start()]);
    expect(ports.first, greaterThan(0));
    expect(ports.last, ports.first);
    expect(server.port, ports.first);
  });

  test('stop pendant ouverture ne laisse pas de serveur ou QR orphelin',
      () async {
    final pending = server.serveBrowser(
      upstreamUrl: 'http://fixture.invalid/a.ts',
      owner: Object(),
    );
    await server.stop();
    expect(await pending, isNull);
    expect(server.isRunning, isFalse);
    expect(server.hasBrowserSession, isFalse);
  });

  test('arrêt du serveur invalide aussi les anciens relais pass-through',
      () async {
    const source = 'http://fixture.invalid/a.ts';
    final relay = await server.registerRelay(
        upstreamUrl: source,
        profile: DlnaProfiles.select(url: source, finalMime: null),
        receiverHost: '192.0.2.1');
    expect(relay, isNotNull);
    final path = Uri.parse(relay!).path;
    await server.stop();
    await server.start();
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.notFound);
    await response.drain<void>();
  });

  test('clearRelay rend le socket fournisseur sans attendre sa fin', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hold = Completer<void>();
    upstream.listen((request) async {
      try {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.bufferOutput = false;
        request.response.add(List<int>.filled(32 * 1024, 1));
        await request.response.flush();
        await hold.future;
        await request.response.close();
      } catch (_) {
        // Fermeture fournisseur attendue à l'arrêt volontaire du Cast.
      }
    });
    try {
      final source = 'http://127.0.0.1:${upstream.port}/a.ts';
      final relay = await server.registerRelay(
          upstreamUrl: source,
          profile: DlnaProfiles.select(url: source, finalMime: null),
          receiverHost: '192.0.2.1');
      expect(relay, isNotNull);
      final request = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${server.port}${Uri.parse(relay!).path}'));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      final received = Completer<void>();
      final ended = Completer<void>();
      response.listen((_) {
        if (!received.isCompleted) received.complete();
      }, onDone: () {
        if (!ended.isCompleted) ended.complete();
      }, onError: (Object _) {
        if (!ended.isCompleted) ended.complete();
      });
      await received.future.timeout(const Duration(seconds: 3));
      server.clearRelay(relay);
      await ended.future.timeout(const Duration(seconds: 3));
      expect(hold.isCompleted, isFalse);
    } finally {
      if (!hold.isCompleted) hold.complete();
      await upstream.close(force: true);
    }
  });

  test('un droit déjà annulé ne démarre aucun serveur', () async {
    expect(
        await server.serveBrowser(
          upstreamUrl: 'http://fixture.invalid/a.ts',
          owner: Object(),
          isCancelled: () => true,
        ),
        isNull);
    expect(server.isRunning, isFalse);
  });

  test('annulation pendant une attente ne publie aucune URL', () async {
    await server.start();
    var cancelled = false;
    final owner = Object();
    final pending = server.serveBrowser(
      upstreamUrl: 'http://fixture.invalid/a.ts',
      owner: owner,
      isCancelled: () => cancelled,
    );
    cancelled = true;
    expect(await pending, isNull);
    expect((await current())['url'], isNull);
  });

  test('ancien propriétaire ne publie ni ne ferme la nouvelle page', () async {
    await server.start();
    final oldOwner = Object();
    final newOwner = Object();
    final old = server.serveBrowser(
      upstreamUrl: 'http://fixture.invalid/a.ts',
      title: 'Ancienne',
      owner: oldOwner,
    );
    final latest = server.serveBrowser(
      upstreamUrl: 'http://fixture.invalid/b.ts',
      title: 'Nouvelle',
      owner: newOwner,
    );
    server.stopBrowser(owner: oldOwner);
    expect(await old, isNull);
    expect(await latest, isNotNull);
    expect((await current())['title'], 'Nouvelle');
    server.stopBrowser(owner: oldOwner);
    expect((await current())['title'], 'Nouvelle');
    server.stopBrowser(owner: newOwner);
    expect((await current())['url'], isNull);
  });

  test('révocation est aussi vérifiée avant exposition de current', () async {
    var cancelled = false;
    expect(
        await server.serveBrowser(
          upstreamUrl: 'http://fixture.invalid/a.ts',
          owner: Object(),
          isCancelled: () => cancelled,
        ),
        isNotNull);
    final oldPath = (await current())['url'] as String;
    cancelled = true;
    expect((await current())['url'], isNull);
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}$oldPath'));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.notFound);
    await response.drain<void>();
  });

  test('remplacement ferme le socket ancien sans arrêter le nouveau', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hold = Completer<void>();
    upstream.listen((request) async {
      try {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.bufferOutput = false;
        request.response.add(List<int>.filled(32 * 1024, 1));
        await request.response.flush();
        if (request.uri.path == '/a.ts') await hold.future;
        await request.response.close();
      } catch (_) {
        // Le test ferme délibérément ce flux pendant l'attente.
      }
    });
    final oldOwner = Object();
    final newOwner = Object();
    final gotData = Completer<void>();
    final ended = Completer<void>();
    try {
      expect(
          await server.serveBrowser(
            upstreamUrl: 'http://127.0.0.1:${upstream.port}/a.ts',
            title: 'Ancienne',
            owner: oldOwner,
          ),
          isNotNull);
      final path = (await current())['url'] as String;
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      response.listen((_) {
        if (!gotData.isCompleted) gotData.complete();
      }, onDone: () {
        if (!ended.isCompleted) ended.complete();
      }, onError: (Object _) {
        if (!ended.isCompleted) ended.complete();
      });
      await gotData.future.timeout(const Duration(seconds: 3));
      expect(
          await server.serveBrowser(
            upstreamUrl: 'http://127.0.0.1:${upstream.port}/b.ts',
            title: 'Nouvelle',
            owner: newOwner,
          ),
          isNotNull);
      server.stopBrowser(owner: oldOwner);
      await ended.future.timeout(const Duration(seconds: 3));
      expect(hold.isCompleted, isFalse,
          reason:
              'le client ancien doit être fermé sans attendre le fournisseur');
      final state = await current();
      expect(state['title'], 'Nouvelle');
      final latest = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}${state['url']}'));
      final latestResponse = await latest.close();
      expect(latestResponse.statusCode, HttpStatus.ok);
      // Le test coupe la réception ensuite : le comportement live historique
      // peut reconnecter un flux sans Content-Length.
      await latestResponse.first;
    } finally {
      if (!hold.isCompleted) hold.complete();
      await upstream.close(force: true);
    }
  });
}
