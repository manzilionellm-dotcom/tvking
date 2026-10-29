import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/playlists/data/source_protocol_fallback.dart';

void main() {
  const String https =
      'https://provider.invalid:443/get.php?username=a%2Bb&password=c%26d&type=m3u_plus';
  const String plain =
      'http://provider.invalid:443/get.php?username=a%2Bb&password=c%26d&type=m3u_plus';

  for (final String url in <String>[https, plain]) {
    test('un lien fonctionnel garde exactement son protocole : $url', () async {
      final List<String> calls = <String>[];
      final result = await SourceProtocolFallback.connect<String>(
        url: url,
        allowHttpCompatibility: true,
        attempt: (String candidate, bool singleAttempt) async {
          calls.add(candidate);
          expect(singleAttempt, isFalse);
          return 'catalogue';
        },
      );
      expect(calls, <String>[url]);
      expect(result.url, url);
      expect(result.value, 'catalogue');
    });
  }

  test('une incompatibilité TLS autorise une seule connexion HTTP exacte', () async {
    final List<String> calls = <String>[];
    final List<bool> single = <bool>[];
    final result = await SourceProtocolFallback.connect<int>(
      url: https,
      allowHttpCompatibility: true,
      attempt: (String candidate, bool singleAttempt) async {
        calls.add(candidate);
        single.add(singleAttempt);
        if (candidate == https) {
          throw const HandshakeException('WRONG_VERSION_NUMBER');
        }
        return 2;
      },
    );
    expect(calls, <String>[https, plain]);
    expect(single, <bool>[false, true]);
    expect(result.url, plain);
    expect(result.value, 2);
  });

  test('les imports automatiques ne changent pas de protocole', () async {
    int attempts = 0;
    await expectLater(SourceProtocolFallback.connect<void>(
      url: https,
      attempt: (_, __) async {
        attempts++;
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      },
    ), throwsA(isA<HandshakeException>()));
    expect(attempts, 1);
  });

  final List<Object> denied = <Object>[
    const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
    const HandshakeException('WRONG_VERSION_NUMBER CERTIFICATE_VERIFY_FAILED'),
    TimeoutException('délai dépassé'),
    http.ClientException('Connection reset'),
    Exception('HTTP 401'),
    Exception('HTTP 403'),
    const FormatException('playlist invalide'),
    Exception('WRONG_VERSION_NUMBER'),
  ];
  for (int index = 0; index < denied.length; index++) {
    test('aucun repli pour un certificat, refus ou contenu invalide #$index', () async {
      int attempts = 0;
      await expectLater(SourceProtocolFallback.connect<void>(
        url: https,
        allowHttpCompatibility: true,
        attempt: (_, __) async {
          attempts++;
          throw denied[index];
        },
      ), throwsA(same(denied[index])));
      expect(attempts, 1);
    });
  }

  test('une erreur TLS typée conservée par http.Client reste reconnue', () {
    expect(SourceProtocolFallback.isProtocolMismatch(http.ClientException(
      'HandshakeException: Handshake error (WRONG_VERSION_NUMBER)',
    )), isTrue);
  });

  test('un échec HTTP est terminal et empêche un deuxième repli get.php', () async {
    final List<String> calls = <String>[];
    await expectLater(SourceProtocolFallback.connect<void>(
      url: https,
      allowHttpCompatibility: true,
      attempt: (String candidate, _) async {
        calls.add(candidate);
        if (candidate == https) {
          throw const HandshakeException('WRONG_VERSION_NUMBER');
        }
        throw Exception('HTTP 403');
      },
    ), throwsA(isA<SourceProtocolFallbackFailure>()));
    expect(calls, <String>[https, plain]);
  });
}
