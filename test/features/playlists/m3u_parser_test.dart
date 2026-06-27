// =========================================================
//  m3u_parser_test.dart — Tests du parser M3U (cœur métier)
// =========================================================
//  Le parsing M3U est CRITIQUE (c'est lui qui transforme la source du client
//  en chaînes). Il n'avait AUCUN test. On couvre ici les cas de base + le
//  garde-fou mémoire (plafond de chaînes), pour empêcher toute régression
//  silencieuse de l'ingestion.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

void main() {
  group('M3uParser.parse', () {
    test('M3U_PLUS : nom, catégorie, logo et URL sont extraits', () {
      const String content = '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="c1" tvg-logo="http://x/a.png" group-title="Sport",Canal Sport\n'
          'http://host/stream1.ts\n';
      final M3uParseResult r = M3uParser.parse(content, playlistId: 1);
      expect(r.channels.length, 1);
      final ch = r.channels.first;
      expect(ch.name, 'Canal Sport');
      expect(ch.category, 'Sport');
      expect(ch.streamUrl, 'http://host/stream1.ts');
      expect(ch.logoUrl, 'http://x/a.png');
    });

    test('M3U simple (URLs sans #EXTINF) est toléré', () {
      const String content = 'http://h/a.ts\nhttp://h/b.ts\n';
      final M3uParseResult r = M3uParser.parse(content, playlistId: 2);
      expect(r.channels.length, 2);
    });

    test('le plafond maxChannels est respecté (anti-OOM)', () {
      final StringBuffer b = StringBuffer('#EXTM3U\n');
      for (int i = 0; i < 50; i++) {
        b.writeln('#EXTINF:-1,Chaîne $i');
        b.writeln('http://host/$i.ts');
      }
      final M3uParseResult r =
          M3uParser.parse(b.toString(), playlistId: 1, maxChannels: 10);
      expect(r.channels.length, 10);
      expect(r.warnings.any((String w) => w.contains('Limite atteinte')), isTrue);
    });

    test('les lignes non-URL sont ignorées sans planter', () {
      const String content = '#EXTM3U\n'
          '#EXTINF:-1,Mauvaise\nceci-nest-pas-une-url\n'
          '#EXTINF:-1,Bonne\nhttp://h/ok.ts\n';
      final M3uParseResult r = M3uParser.parse(content, playlistId: 3);
      expect(r.channels.length, 1);
      expect(r.channels.first.name, 'Bonne');
    });
  });
}
