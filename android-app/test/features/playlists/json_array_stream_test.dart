// JsonArrayStream doit rendre EXACTEMENT les mêmes éléments que jsonDecode
// (le décodage complet d'avant), un par un, et refuser les mêmes entrées
// invalides. Données synthétiques uniquement.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/json_array_stream.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

List<Object?> _stream(String s) => JsonArrayStream.elements(_bytes(s)).toList();

/// Valeur JSON aléatoire, avec les pièges du découpage : accolades et
/// crochets DANS les chaînes, guillemets et barres obliques échappés,
/// Unicode, imbrications.
Object? _randomValue(math.Random r, int depth) {
  switch (r.nextInt(depth > 3 ? 5 : 7)) {
    case 0:
      return r.nextInt(1 << 20) - 1000;
    case 1:
      return r.nextDouble() * 1e6;
    case 2:
      return r.nextBool();
    case 3:
      return null;
    case 4:
      const List<String> pieces = <String>[
        'TF1 HD', '{', '}', '[', ']', '"', r'\', ',', 'é', '日本', '😀', ' ', r'\n', '\t',
      ];
      return List<String>.generate(r.nextInt(6), (_) => pieces[r.nextInt(pieces.length)]).join();
    case 5:
      return <String, Object?>{
        for (int i = 0; i < r.nextInt(5); i++) 'k$i${'{['[i % 2]}': _randomValue(r, depth + 1),
      };
    default:
      return <Object?>[for (int i = 0; i < r.nextInt(4); i++) _randomValue(r, depth + 1)];
  }
}

void main() {
  test('identique à jsonDecode sur 300 tableaux aléatoires', () {
    final math.Random r = math.Random(7);
    for (int n = 0; n < 300; n++) {
      final List<Object?> value = <Object?>[for (int i = 0; i < r.nextInt(12); i++) _randomValue(r, 0)];
      // Espaces variés autour des séparateurs.
      final String compact = jsonEncode(value);
      final String spaced = const JsonEncoder.withIndent('  ').convert(value);
      for (final String text in <String>[compact, spaced, '  \r\n$spaced\n ']) {
        expect(_stream(text), jsonDecode(text), reason: text);
      }
    }
  });

  test('objets Xtream typiques : mêmes Map, même ordre', () {
    final String body = jsonEncode(<Map<String, Object?>>[
      for (int i = 0; i < 50; i++)
        <String, Object?>{
          'num': i,
          'name': 'FR| L’équipe {$i} "live" [HD] \\ fin',
          'stream_id': 1000 + i,
          'stream_icon': i.isEven ? 'http://logo.invalid/$i.png' : '',
          'epg_channel_id': i % 3 == 0 ? null : 'c$i.fr',
          'category_ids': <int>[i, i + 1],
          'tv_archive': i % 2,
        },
    ]);
    final List<Object?> items = _stream(body);
    expect(items, jsonDecode(body));
    expect(items.first, isA<Map<String, dynamic>>());
  });

  test('BOM UTF-8, tableau vide et éléments non-objets', () {
    expect(JsonArrayStream.elements(Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('[1,{"a":2}]')])).toList(),
        <Object?>[1, <String, Object?>{'a': 2}]);
    expect(_stream('[]'), isEmpty);
    expect(_stream(' [ ] '), isEmpty);
    expect(_stream('["a", 3, null, true, [1], {"x": "}"}]'), jsonDecode('["a", 3, null, true, [1], {"x": "}"}]'));
  });

  test('UTF-8 malformé toléré comme avant (allowMalformed)', () {
    final Uint8List bad = Uint8List.fromList(<int>[...utf8.encode('[{"name":"A'), 0xFF, ...utf8.encode('B"}]')]);
    final List<Object?> items = JsonArrayStream.elements(bad).toList();
    expect((items.single! as Map<String, dynamic>)['name'], 'A�B');
  });

  test('entrées invalides refusées comme par jsonDecode', () {
    for (final String bad in <String>[
      '',
      '   ',
      '{"data": []}', // pas un tableau : l'appelant garde l'ancien chemin
      '[',
      '[{"a":1}',
      '[{"a":1},',
      '[{"a":1},]',
      '[,]',
      '[{"a":1} {"b":2}]',
      '[{"a":"non terminé}]',
      '[{"a":1}] reste',
      '[{"a":1}]]',
      '[abc]',
      '[1}]',
      '[{"a":}]',
    ]) {
      expect(() => _stream(bad), throwsFormatException, reason: bad);
      expect(() => jsonDecode(bad) as List<Object?>, throwsA(anything), reason: bad);
    }
  });

  test('isTopLevelArray distingue tableau et enveloppe', () {
    expect(JsonArrayStream.isTopLevelArray(_bytes(' \n [1]')), isTrue);
    expect(JsonArrayStream.isTopLevelArray(_bytes('{"data":[1]}')), isFalse);
    expect(JsonArrayStream.isTopLevelArray(_bytes('')), isFalse);
  });

  test('élément par élément : on peut s’arrêter avant la fin sans tout décoder', () {
    // Le 3e élément est invalide : on ne doit pas l'atteindre si l'on
    // s'arrête après deux (plafond d'import atteint).
    final Iterable<Object?> it = JsonArrayStream.elements(_bytes('[{"a":1},{"a":2},{"a":}]'));
    expect(it.take(2).toList(), <Object?>[<String, Object?>{'a': 1}, <String, Object?>{'a': 2}]);
    expect(() => it.toList(), throwsFormatException);
  });

  group('fields (lecture des seules clés utiles)', () {
    const Set<String> wanted = <String>{
      'stream_id', 'name', 'category_id', 'stream_icon', 'tv_archive',
      'tv_archive_duration', 'epg_channel_id',
    };

    Map<String, Object?> read(String json) {
      final Uint8List b = _bytes(json);
      final (int s, int e) = JsonArrayStream.spans(_bytes('[$json]')).single;
      // Les bornes sont décalées d'un octet (le « [ ») : on relit à part.
      return JsonArrayStream.fields(b, s - 1, e - 1, wanted);
    }

    test('mêmes valeurs que jsonDecode pour 500 objets aléatoires', () {
      final math.Random r = math.Random(11);
      for (int n = 0; n < 500; n++) {
        final Map<String, Object?> obj = <String, Object?>{};
        for (final String k in <String>[
          'num', 'name', 'stream_type', 'stream_id', 'stream_icon', 'epg_channel_id',
          'added', 'category_id', 'category_ids', 'custom_sid', 'tv_archive',
          'direct_source', 'tv_archive_duration', 'is_adult',
        ]) {
          if (r.nextInt(6) == 0) continue; // champ parfois absent
          obj[k] = _randomValue(r, 1);
        }
        final String json = r.nextBool()
            ? jsonEncode(obj)
            : const JsonEncoder.withIndent(' ').convert(obj);
        final Map<String, dynamic> full = jsonDecode(json) as Map<String, dynamic>;
        final Map<String, Object?> got = read(json);
        expect(got.keys.toSet(), full.keys.toSet().intersection(wanted), reason: json);
        for (final String k in got.keys) {
          expect(got[k], full[k], reason: '$k dans $json');
          expect(got[k]?.toString(), full[k]?.toString(), reason: '$k dans $json');
        }
      }
    });

    test('clé répétée : la dernière valeur gagne, comme une Map décodée', () {
      expect(read('{"name":"A","name":"B"}')['name'], 'B');
    });

    test('échappements dans les clés et les valeurs', () {
      final Map<String, Object?> got =
          read(r'{"name":"L’équipe \"HD\" \\ \/","stream_id":"7"}');
      expect(got['name'], 'L’équipe "HD" \\ /');
      expect(got['stream_id'], '7');
    });

    test('objets mal formés refusés', () {
      for (final String bad in <String>[
        '{"name":"A",}',
        '{"name" "A"}',
        '{"name":}',
        '{name:"A"}',
        '{"name":"A" "x":1}',
      ]) {
        expect(() => JsonArrayStream.fields(_bytes(bad), 0, _bytes(bad).length, wanted),
            throwsFormatException, reason: bad);
      }
      expect(read('{}'), isEmpty);
    });
  });
}
