import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/phone_remote/data/phone_remote_bus.dart';
import 'package:tv_king/features/phone_remote/data/phone_remote_session.dart';
import 'package:tv_king/features/phone_remote/domain/remote_command.dart';
import 'package:tv_king/features/phone_remote/domain/remote_page.dart';

void main() {
  test('un ordre inconnu est ignoré', () {
    expect(RemoteCommands.parse('up'), RemoteCommand.up);
    expect(RemoteCommands.parse('play'), RemoteCommand.playPause);
    expect(RemoteCommands.parse('open-url'), isNull);
    expect(RemoteCommands.parse(null), isNull);
  });

  test('la page du téléphone ne charge rien à l\'extérieur', () {
    final String page = remoteControlPage('abc123');
    expect(page.contains('https://'), isFalse);
    expect(page.contains('src='), isFalse);
    expect(page.contains('Haut'), isTrue);
    expect(page.contains('abc123'), isTrue);
  });

  test('le serveur refuse sans jeton et transmet un ordre connu', () async {
    await PhoneRemoteSession.flag.set(true);
    await PhoneRemoteSession.instance.ensureStarted();
    final String? url = PhoneRemoteSession.instance.url;
    // Sur une machine sans adresse locale, on s'arrête là : ce n'est
    // pas un échec de la télécommande, c'est l'absence de Wi-Fi.
    if (url == null) {
      expect(PhoneRemoteSession.instance.running, isFalse);
      return;
    }
    final Uri page = Uri.parse(url);
    final HttpClient client = HttpClient();
    try {
      final Uri missing = page.replace(queryParameters: <String, String>{});
      final HttpClientRequest refused =
          await client.getUrl(missing);
      final HttpClientResponse refusedRes = await refused.close();
      expect(refusedRes.statusCode, 404);
      await refusedRes.drain<void>();

      final Future<RemoteCommand> got =
          PhoneRemoteBus.instance.stream.first;
      final Uri cmd = page.replace(path: '/cmd', queryParameters: <String, String>{
        't': page.queryParameters['t']!,
        'c': 'ok',
      });
      final HttpClientRequest sent = await client.postUrl(cmd);
      final HttpClientResponse sentRes = await sent.close();
      expect(sentRes.statusCode, 204);
      await sentRes.drain<void>();
      expect(await got, RemoteCommand.ok);

      final Uri bad = cmd.replace(queryParameters: <String, String>{
        't': page.queryParameters['t']!,
        'c': 'format-disk',
      });
      final HttpClientRequest badReq = await client.postUrl(bad);
      final HttpClientResponse badRes = await badReq.close();
      expect(badRes.statusCode, 400);
      await badRes.drain<void>();

      final HttpClientRequest htmlReq = await client.getUrl(page);
      final HttpClientResponse htmlRes = await htmlReq.close();
      final String body = await htmlRes.transform(utf8.decoder).join();
      expect(body.contains('ZUNO'), isTrue);
    } finally {
      client.close(force: true);
      await PhoneRemoteSession.instance.stop();
    }
  });
}
