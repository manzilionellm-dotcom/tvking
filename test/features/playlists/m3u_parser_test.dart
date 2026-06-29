// =========================================================
//  m3u_parser_test.dart — verrouille le parsing M3U / M3U_PLUS
// =========================================================
//  Le parsing de playlist est le CŒUR d'une app IPTV : s'il régresse,
//  des milliers de chaînes disparaissent ou se mélangent. Ces tests
//  figent le comportement attendu du parser ultra-tolérant (M3uParser)
//  sur les cas réels du marché : M3U_PLUS, M3U simple, BOM, CRLF, header
//  absent, #EXTGRP séparé, attributs sans guillemets, virgule dans un
//  attribut quoté, lignes non-URL, fallback de nom.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

String _m3u(List<String> lines) => lines.join('\n');

void main() {
  group('M3uParser.parse', () {
    test('M3U_PLUS : nom, id (tvg-id), catégorie (group-title), logo, URL', () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          '#EXTINF:-1 tvg-id="c1" tvg-logo="http://logo/c1.png" '
              'group-title="Sport",Canal+ Sport',
          'http://host/live/u/p/1.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      final Channel c = r.channels.first;
      expect(c.name, 'Canal+ Sport');
      expect(c.id, 'c1'); // tvg-id prioritaire
      expect(c.category, 'Sport');
      expect(c.logoUrl, 'http://logo/c1.png');
      expect(c.streamUrl, 'http://host/live/u/p/1.ts');
      expect(c.isLive, isTrue);
    });

    test('M3U simple (URLs seules) : nom auto « Chaîne N », catégorie Autres',
        () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          'http://host/a.ts',
          'http://host/b.ts',
        ]),
        playlistId: 7,
      );
      expect(r.channels, hasLength(2));
      expect(r.channels[0].name, 'Chaîne 1');
      expect(r.channels[1].name, 'Chaîne 2');
      expect(r.channels[0].category, 'Autres');
      expect(r.channels[0].id, 'm3u-7-0');
      expect(r.channels[1].id, 'm3u-7-1');
    });

    test('BOM UTF-8 strippé + header #EXTM3U absent → parse quand même', () {
      final M3uParseResult r = M3uParser.parse(
        '\u{FEFF}${_m3u(<String>[
          '#EXTINF:-1,Test',
          'http://h/x.ts',
        ])}',
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.name, 'Test');
      // Sans #EXTM3U on prévient mais on n'échoue pas.
      expect(r.warnings.any((String w) => w.contains('#EXTM3U')), isTrue);
    });

    test('Sauts de ligne CRLF (\\r\\n) normalisés', () {
      final M3uParseResult r = M3uParser.parse(
        '#EXTM3U\r\n#EXTINF:-1,A\r\nhttp://h/a.ts\r\n',
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.name, 'A');
    });

    test('#EXTGRP: sur ligne séparée → catégorie de la chaîne suivante', () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          '#EXTGRP:Movies',
          '#EXTINF:-1,Film1',
          'http://h/f.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.category, 'Movies');
      expect(r.channels.first.name, 'Film1');
    });

    test('Attributs SANS guillemets (tvg-id=x group-title=News)', () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          '#EXTINF:-1 tvg-id=ch5 group-title=News,Info Channel',
          'http://h/n.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      final Channel c = r.channels.first;
      expect(c.id, 'ch5');
      expect(c.category, 'News');
      expect(c.name, 'Info Channel');
    });

    test('Virgule DANS un attribut quoté ne casse pas le séparateur de nom',
        () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          '#EXTINF:-1 tvg-name="A, B" group-title="X",Real Name',
          'http://h/x.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.name, 'Real Name');
      expect(r.channels.first.category, 'X');
    });

    test('Ligne non-URL ignorée (warning) sans casser le reste', () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          'ceci nest pas une url',
          'http://h/a.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.streamUrl, 'http://h/a.ts');
      expect(r.warnings.any((String w) => w.contains('ignorée')), isTrue);
    });

    test('catchup → catchupSupported = true', () {
      final M3uParseResult r = M3uParser.parse(
        _m3u(<String>[
          '#EXTM3U',
          '#EXTINF:-1 catchup="default" catchup-days="7",Replay Ch',
          'http://h/r.ts',
        ]),
        playlistId: 1,
      );
      expect(r.channels, hasLength(1));
      expect(r.channels.first.catchupSupported, isTrue);
    });

    test('Contenu vide → 0 chaîne, ne jette pas', () {
      final M3uParseResult r = M3uParser.parse('', playlistId: 1);
      expect(r.channels, isEmpty);
    });
  });
}
