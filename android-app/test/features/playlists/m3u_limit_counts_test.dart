import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

String _playlist(int count) {
  final body = StringBuffer('#EXTM3U\n');
  for (var i = 0; i < count; i++) {
    body.writeln('http://127.0.0.1/fixture/$i.ts');
  }
  return body.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('50 000 entrées et commentaires : aucune troncature inventée', () {
    final parsed = M3uParser.parse(
      '${_playlist(50000)}# commentaire\n#EXTINF:-1,Inachevé\npas-de-media\n',
      playlistId: 4,
      reportLimit: true,
    );
    expect(parsed.channels, hasLength(50000));
    expect(parsed.importCounts!.validEntries, 50000);
    expect(parsed.importCounts!.truncated, isFalse);
    expect(parsed.warnings.where((text) => text.contains('Limite')), isEmpty);
  });

  test(
    '100 003 entrées : objets bornés, reste compté sans le déclarer stocké',
    () {
      final parsed = M3uParser.parse(
        _playlist(100003),
        playlistId: 4,
        reportLimit: true,
      );
      expect(parsed.channels, hasLength(50000));
      expect(parsed.channels.first.id, 'm3u-4-0');
      expect(parsed.channels.last.id, 'm3u-4-49999');
      expect(parsed.importCounts!.validEntries, 100003);
      expect(parsed.importCounts!.retainedEntries, 50000);
      expect(parsed.importCounts!.skippedEntries, 50003);
      expect(parsed.importCounts!.truncated, isTrue);
      expect(
        parsed.warnings.where((text) => text.contains('Limite')),
        hasLength(1),
      );
    },
  );

  test('les deux entrées isolate transportent le compte réel', () async {
    final input = _playlist(50003);
    final text = await M3uParser.parseInBackground(
      input,
      playlistId: 7,
      reportLimit: true,
    );
    final bytes = await M3uParser.parseBytesInBackground(
      Uint8List.fromList(utf8.encode(input)),
      playlistId: 7,
      reportLimit: true,
    );
    for (final parsed in [text, bytes]) {
      expect(parsed.channels, hasLength(50000));
      expect(parsed.importCounts!.validEntries, 50003);
      expect(parsed.importCounts!.skippedEntries, 3);
    }
    expect(
      text.channels.map((channel) => channel.id),
      bytes.channels.map((channel) => channel.id),
    );
  });

  test('chemin historique par défaut conservé et compte vide explicite', () {
    final historic = M3uParser.parse(
      '${_playlist(50000)}# fin\n',
      playlistId: 1,
    );
    expect(historic.channels, hasLength(50000));
    expect(historic.importCounts, isNull);
    expect(
      historic.warnings.where((text) => text.contains('Limite')),
      hasLength(1),
    );
    final empty = M3uParser.parse('', playlistId: 1, reportLimit: true);
    expect(empty.importCounts!.validEntries, 0);
    expect(empty.importCounts!.truncated, isFalse);
  });
}
