// =========================================================
//  live_fallback_test.dart — Secours du direct
// =========================================================
//  Adresses factices (example.invalid) : aucune URL de flux réelle.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/domain/live_fallback.dart';

Channel _ch(String id, String name, String url, {bool live = true}) => Channel(
      id: id,
      name: name,
      category: 'Test',
      streamUrl: url,
      isLive: live,
    );

void main() {
  setUp(LiveFallback.resetMemory);

  const String ts = 'http://a.example.invalid:8080/live/u/p/123.ts';

  test('formats Xtream : .ts → .m3u8 puis ancien chemin, sans l\'original', () {
    expect(LiveFallback.formatVariants(ts), <String>[
      'http://a.example.invalid:8080/live/u/p/123.m3u8',
      'http://a.example.invalid:8080/u/p/123',
    ]);
    // Ancien chemin sans extension → reconnu aussi.
    expect(LiveFallback.formatVariants('http://a.example.invalid/u/p/9'),
        contains('http://a.example.invalid/live/u/p/9.ts'));
  });

  test('films / séries / adresses non Xtream : aucun format inventé', () {
    expect(LiveFallback.formatVariants('http://a.example.invalid/movie/u/p/5.mkv'), isEmpty);
    expect(LiveFallback.formatVariants('http://a.example.invalid/series/u/p/5.mp4'), isEmpty);
    expect(LiveFallback.formatVariants('https://cdn.example.invalid/chaine/index.m3u8'), isEmpty);
    expect(LiveFallback.formatVariants('http://a.example.invalid/live/u/p/abc.ts'), isEmpty);
  });

  test('nom comparable : pays, qualité et ponctuation ignorés', () {
    expect(LiveFallback.matchKey('FR: TF1 FHD'), 'tf1');
    expect(LiveFallback.matchKey('|FR| TF1 HD'), 'tf1');
    expect(LiveFallback.matchKey('TF1 4K'), 'tf1');
    expect(LiveFallback.matchKey('M6'), 'm6');
    expect(LiveFallback.matchKey('Sky Sports 1 HD'), LiveFallback.matchKey('UK: Sky Sports 1'));
    expect(LiveFallback.matchKey('TF1'), isNot(LiveFallback.matchKey('TF1 Séries Films')));
  });

  test('candidats : original, formats, puis la même chaîne ailleurs (autre serveur d\'abord)', () {
    final Channel cur = _ch('1', 'FR: TF1 HD', ts);
    final List<Channel> all = <Channel>[
      cur,
      _ch('2', 'TF1 FHD', 'http://a.example.invalid:8080/live/u/p/777.ts'), // même serveur
      _ch('3', '|FR| TF1', 'http://b.example.invalid/live/x/y/55.ts'), // autre serveur
      _ch('4', 'TF1 Séries Films', 'http://b.example.invalid/live/x/y/56.ts'), // autre chaîne
      _ch('5', 'TF1', 'http://b.example.invalid/movie/x/y/57.mp4', live: false), // film
    ];
    final List<String> c = LiveFallback.candidates(cur, all);
    expect(c.first, ts);
    expect(c.sublist(1, 3), LiveFallback.formatVariants(ts));
    expect(c.sublist(3), <String>[
      'http://b.example.invalid/live/x/y/55.ts',
      'http://a.example.invalid:8080/live/u/p/777.ts',
    ]);
    expect(c.toSet().length, c.length, reason: 'aucun doublon');
  });

  test('mémoire : le format qui a marché devient le 1er pour ce serveur', () {
    expect(LiveFallback.preferred(ts), ts);
    LiveFallback.remember(ts, 'http://a.example.invalid:8080/live/u/p/123.m3u8');
    expect(LiveFallback.preferred('http://a.example.invalid:8080/live/u/p/456.ts'),
        'http://a.example.invalid:8080/live/u/p/456.m3u8');
    // Autre serveur : inchangé.
    expect(LiveFallback.preferred('http://b.example.invalid/live/x/y/1.ts'),
        'http://b.example.invalid/live/x/y/1.ts');
    // Une copie trouvée sur un AUTRE serveur ne modifie pas la mémoire.
    LiveFallback.remember('http://b.example.invalid/live/x/y/1.ts', ts);
    expect(LiveFallback.preferred('http://b.example.invalid/live/x/y/2.ts'),
        'http://b.example.invalid/live/x/y/2.ts');
  });
}
