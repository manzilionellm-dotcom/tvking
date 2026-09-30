// =========================================================
//  remote_rules_test.dart — Règles de la télécommande, sans réseau
// =========================================================
//  Jeton imprévisible, un seul téléphone, expiration, liste fermée
//  des commandes, texte nettoyé, choix de l'adresse Wi-Fi.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/remote/data/remote_page.dart';
import 'package:tv_king/features/remote/domain/lan_ipv4.dart';
import 'package:tv_king/features/remote/domain/remote_command.dart';
import 'package:tv_king/features/remote/domain/remote_session.dart';
import 'package:tv_king/features/remote/domain/remote_token.dart';
import 'package:tv_king/features/remote/domain/remote_typing_hub.dart';

void main() {
  test('le jeton fait 128 bits, hex, et change à chaque fois', () {
    final Set<String> seen = <String>{};
    for (int i = 0; i < 40; i++) {
      final String token = newRemoteToken();
      expect(token, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue);
      seen.add(token);
    }
    expect(seen, hasLength(40));
  });

  test('comparaison : égal, différent, longueur différente', () {
    expect(constantTimeEquals('abcd', 'abcd'), isTrue);
    expect(constantTimeEquals('abcd', 'abce'), isFalse);
    expect(constantTimeEquals('abcd', 'abc'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });

  test('sans appairage, rien ; un seul téléphone ; l\'expiration coupe', () {
    var now = DateTime.utc(2026, 9, 30, 12);
    final RemoteSession session = RemoteSession.issue(clock: () => now);
    expect(session.isPaired, isFalse);
    expect(session.matches('quelqu-un'), isFalse);
    expect(session.secondsLeft, kRemoteSessionTtl.inSeconds);

    expect(session.pairNewPhone('phone-a'), 'phone-a');
    expect(session.isPaired, isTrue);
    expect(session.matches('phone-a'), isTrue);
    // Le deuxième téléphone, même très rapide, est refusé.
    expect(session.pairNewPhone('phone-b'), isNull);
    expect(session.matches('phone-b'), isFalse);
    // Le jeton de l'adresse n'est pas le cookie : les confondre ne marche pas.
    expect(session.matches(session.token), isFalse);

    now = now.add(kRemoteSessionTtl);
    expect(session.isExpired, isTrue);
    expect(session.isPaired, isFalse);
    expect(session.matches('phone-a'), isFalse);
    expect(session.pairNewPhone('phone-c'), isNull);
    expect(session.secondsLeft, 0);
  });

  test('texte : contrôles et bidi retirés, trop long refusé, vide accepté', () {
    expect(sanitizeRemoteText('TF1'), 'TF1');
    expect(sanitizeRemoteText('a\nb\u0000c'), 'abc');
    expect(sanitizeRemoteText('ok\u202Eevil'), 'okevil');
    expect(sanitizeRemoteText(''), '');
    expect(sanitizeRemoteText('é' * kRemoteTextMax), 'é' * kRemoteTextMax);
    expect(sanitizeRemoteText('a' * (kRemoteTextMax + 1)), isNull);
  });

  test('liste fermée : touches connues, texte, et refus du reste', () {
    expect(parseRemoteCommand(<String, Object>{'a': 'up'}), isA<RemotePress>());
    expect(
      (parseRemoteCommand(<String, Object>{'a': 'vol_up'}) as RemotePress)
          .button,
      RemoteButton.volumeUp,
    );
    expect(
      (parseRemoteCommand(<String, Object>{'a': 'query', 't': 'tf\n1'})
              as RemoteQuery)
          .text,
      'tf1',
    );
    expect(parseRemoteCommand(<String, Object>{'a': 'query', 't': ''}),
        isA<RemoteQuery>());
    expect(parseRemoteCommand(<String, Object>{'a': 'reboot'}), isNull);
    expect(parseRemoteCommand(<String, Object>{'a': 'query'}), isNull);
    expect(parseRemoteCommand(<String, Object>{'a': 'query', 't': 1}), isNull);
    expect(parseRemoteCommand('up'), isNull);
    expect(parseRemoteCommand(<String, Object>{'a': 'UP'}), isNull);
  });

  test('la page du téléphone ne contient que des actions autorisées', () {
    final String html = remoteControlPageHtml();
    expect(html, isNot(contains('<script src')));
    expect(html, isNot(contains('http://')));
    expect(html, isNot(contains('https://')));
    final RegExp holds = RegExp(r"bindHold\(\s*'[^']+'\s*,\s*'([a-z_]+)'\s*\)");
    final RegExp taps = RegExp(r"bindTap\(\s*'[^']+'\s*,\s*'([a-z_]+)'\s*\)");
    final Set<String> actions = <String>{
      ...holds.allMatches(html).map((RegExpMatch m) => m.group(1)!),
      ...taps.allMatches(html).map((RegExpMatch m) => m.group(1)!),
    };
    expect(html, contains("send('query'"));
    expect(actions, kRemoteButtonNames.keys.toSet());
    for (final String name in actions) {
      expect(
          parseRemoteCommand(<String, Object>{'a': name}), isA<RemotePress>());
    }
  });

  test('adresse : Wi-Fi d\'abord, câble sinon, jamais VPN ni public', () {
    expect(
      pickLanIpv4(const <LanIface>[
        LanIface('eth0', <String>['192.168.1.10']),
        LanIface('wlan0', <String>['192.168.1.20']),
      ]),
      '192.168.1.20',
    );
    expect(
      pickLanIpv4(const <LanIface>[
        LanIface('eth0', <String>['10.0.0.8']),
      ]),
      '10.0.0.8',
    );
    expect(
      pickLanIpv4(const <LanIface>[
        LanIface('tun0', <String>['10.8.0.2']),
        LanIface('rmnet0', <String>['10.1.2.3']),
        LanIface('docker0', <String>['172.17.0.1']),
        LanIface('eth0', <String>['8.8.8.8', '127.0.0.1']),
      ]),
      isNull,
    );
    expect(isPrivateLanIpv4('172.16.5.1'), isTrue);
    expect(isPrivateLanIpv4('172.15.5.1'), isFalse);
    expect(isPrivateLanIpv4('172.32.0.1'), isFalse);
    expect(isPrivateLanIpv4('169.254.1.1'), isFalse);
    expect(isPrivateLanIpv4('100.64.0.1'), isFalse);
  });

  test('un client Internet est refusé, la boucle locale seulement en test', () {
    final InternetAddress lan = InternetAddress('192.168.0.12');
    final InternetAddress pub = InternetAddress('8.8.8.8');
    final InternetAddress loop = InternetAddress.loopbackIPv4;
    expect(remoteClientAllowed(lan, allowLoopback: false), isTrue);
    expect(remoteClientAllowed(pub, allowLoopback: false), isFalse);
    expect(remoteClientAllowed(pub, allowLoopback: true), isFalse);
    expect(remoteClientAllowed(loop, allowLoopback: false), isFalse);
    expect(remoteClientAllowed(loop, allowLoopback: true), isTrue);
    expect(
      remoteClientAllowed(InternetAddress.loopbackIPv6, allowLoopback: true),
      isFalse,
    );
  });

  test('le texte va au dernier écran qui l\'accepte', () {
    final List<String> order = <String>[];
    bool a(String text) {
      order.add('a');
      return false;
    }

    bool b(String text) {
      order.add('b:$text');
      return true;
    }

    final RemoteTypingHub hub = RemoteTypingHub.instance;
    hub.register(a);
    hub.register(b);
    expect(hub.apply('tf1'), isTrue);
    expect(order, <String>['b:tf1']);
    hub.unregister(b);
    order.clear();
    expect(hub.apply('x'), isFalse);
    expect(order, <String>['a']);
    hub.unregister(a);
    expect(hub.apply('y'), isFalse);
  });
}
