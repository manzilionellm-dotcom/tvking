import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/playlist_secret.dart';

void main() {
  final List<int> key = List<int>.generate(32, (int i) => i + 1);

  setUp(() {
    PlaylistSecret.keyLoader = () async => key;
  });

  tearDown(() {
    PlaylistSecret.keyLoader = null;
  });

  test('chiffre puis relit le mot de passe', () async {
    final String? sealed = await PlaylistSecret.seal('code-xtream');
    expect(sealed, isNotNull);
    expect(sealed!.startsWith(PlaylistSecret.prefix), isTrue);
    expect(sealed.contains('code-xtream'), isFalse);
    expect(await PlaylistSecret.open(sealed), 'code-xtream');
  });

  test('une ancienne ligne en clair reste lisible', () async {
    expect(await PlaylistSecret.open('ancien'), 'ancien');
  });

  test('le préfixe n\'est pas du base64 quelconque', () async {
    final String? sealed = await PlaylistSecret.seal('x');
    expect(base64Url.decode(sealed!.substring(PlaylistSecret.prefix.length)),
        isNotEmpty);
  });
}
