import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/realtime/device_session.dart';

const String _keyName = 'atlas.installation-key';
const String _tokenName = 'atlas.device-token';
final String _existingKey = '1' * 64;

void main() {
  test('réutilise exactement la clé canonique et laisse le jeton intact',
      () async {
    final store = <String, String>{
      _keyName: _existingKey,
      _tokenName: 'fixture-token-existing',
    };
    final writes = <String>[];
    final session = DeviceSession.forTesting(
      read: (key) async => store[key],
      write: (key, value) async {
        writes.add(key);
        store[key] = value;
      },
      deviceId: () async => 'fixture-real-android-id',
    );
    final identity = await session.credentials();
    expect(identity?.deviceKey, _existingKey);
    expect(identity?.deviceId, 'fixture-real-android-id');
    expect(await session.token(), 'fixture-token-existing');
    expect(writes, isEmpty);
    expect(await session.headers(), <String, String>{
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'X-Device-Key': _existingKey,
      'X-Device-Id': 'fixture-real-android-id',
    });
  });

  test('création unique, persistée et relue avant vingt appels concurrents',
      () async {
    final store = <String, String>{};
    final writes = <String>[];
    final barrier = Completer<void>();
    final session = DeviceSession.forTesting(
      read: (key) async {
        await barrier.future;
        return store[key];
      },
      write: (key, value) async {
        writes.add(key);
        store[key] = value;
      },
      deviceId: () async => 'fixture-android-id',
    );
    final pending = List.generate(20, (_) => session.credentials());
    barrier.complete();
    final identities = await Future.wait(pending);
    expect(store[_keyName], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(writes, <String>[_keyName]);
    expect(identities.every((value) => value?.deviceKey == store[_keyName]),
        isTrue);
    final reopened = DeviceSession.forTesting(
      read: (key) async => store[key],
      write: (_, __) async =>
          fail('une clé persistée ne doit pas être réécrite'),
      deviceId: () async => 'fixture-android-id',
    );
    expect((await reopened.credentials())?.deviceKey, store[_keyName]);
  });

  for (final invalid in <String>['', 'not-a-canonical-key', 'A' * 64]) {
    test(
        'une entrée préexistante invalide ne déclenche aucun remplacement (${invalid.length})',
        () async {
      int writes = 0;
      final session = DeviceSession.forTesting(
        read: (_) async => invalid,
        write: (_, __) async {
          writes++;
        },
        deviceId: () async => 'fixture-android-id',
      );
      expect(await session.credentials(), isNull);
      expect(writes, 0);
      final headers = await session.headers();
      expect(headers.containsKey('X-Device-Key'), isFalse);
      expect(headers.containsKey('X-Device-Id'), isFalse);
    });
  }

  test(
      'lecture indisponible : aucun nouveau secret, puis reprise avec la même clé',
      () async {
    bool unavailable = true;
    final session = DeviceSession.forTesting(
      read: (_) async {
        if (unavailable) throw StateError('coffre fermé');
        return _existingKey;
      },
      write: (_, __) async =>
          fail('aucun remplacement après erreur de lecture'),
      deviceId: () async => 'fixture-android-id',
    );
    expect(await session.credentials(), isNull);
    unavailable = false;
    expect((await session.credentials())?.deviceKey, _existingKey);
  });

  test('écriture non persistée : jamais de clé éphémère sur le réseau',
      () async {
    final session = DeviceSession.forTesting(
      read: (_) async => null,
      write: (_, __) async {},
      deviceId: () async => 'fixture-android-id',
    );
    expect(await session.credentials(), isNull);
  });

  test('écriture enregistrée puis erreur : la prochaine passe récupère la clé',
      () async {
    final store = <String, String>{};
    int writes = 0;
    final session = DeviceSession.forTesting(
      read: (key) async => store[key],
      write: (key, value) async {
        writes++;
        store[key] = value;
        throw StateError('accusé perdu');
      },
      deviceId: () async => 'fixture-android-id',
    );
    expect(await session.credentials(), isNull);
    final persisted = store[_keyName];
    expect((await session.credentials())?.deviceKey, persisted);
    expect(writes, 1);
  });

  for (final id in <String>['', 'bad id', 'bad\nid', 'x' * 257]) {
    test(
        'identifiant Android manquant/invalide : pas de création (${id.length})',
        () async {
      int reads = 0;
      int writes = 0;
      final session = DeviceSession.forTesting(
        read: (_) async {
          reads++;
          return null;
        },
        write: (_, __) async {
          writes++;
        },
        deviceId: () async => id,
      );
      expect(await session.credentials(), isNull);
      expect(reads, 0);
      expect(writes, 0);
    });
  }

  test('jeton renouvelé dans sa seule entrée, sans changer la clé', () async {
    final store = <String, String>{_keyName: _existingKey};
    final writes = <String>[];
    final session = DeviceSession.forTesting(
      read: (key) async => store[key],
      write: (key, value) async {
        writes.add(key);
        store[key] = value;
      },
      deviceId: () async => 'fixture-android-id',
    );
    await session.accept(<String, dynamic>{});
    await session.accept(<String, dynamic>{'device_token': ''});
    await session.accept(<String, dynamic>{'device_token': 42});
    expect(writes, isEmpty);
    await session
        .accept(<String, dynamic>{'device_token': 'fixture-token-renewed'});
    expect(writes, <String>[_tokenName]);
    expect(await session.token(), 'fixture-token-renewed');
    expect(store[_keyName], _existingKey);
  });

  test('coffre jeton indisponible : échec fermé sans exception publique',
      () async {
    final session = DeviceSession.forTesting(
      read: (_) async => throw StateError('coffre fermé'),
      write: (_, __) async => throw StateError('coffre fermé'),
      deviceId: () async => throw StateError('pont Android indisponible'),
    );
    expect(await session.credentials(), isNull);
    await session.accept(<String, dynamic>{'device_token': 'fixture-token'});
    expect(await session.token(), isNull);
  });
}
