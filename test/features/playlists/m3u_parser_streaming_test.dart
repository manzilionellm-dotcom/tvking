// =========================================================
//  m3u_parser_streaming_test.dart — équivalence parse / parseStreaming
// =========================================================
//  parseStreaming est la variante ANTI-OOM (pas de copie isolate, pas de
//  liste de lignes matérialisée) utilisée en production pour l'import.
//  Ce test VERROUILLE qu'elle produit EXACTEMENT le même résultat que
//  parse() — sinon le passage au streaming pourrait dégrader/perdre des
//  chaînes sans qu'on le voie. Tests purs (pas de binding ni de réseau).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

// Signature comparable d'une chaîne (les champs qui comptent pour l'import).
String _sig(Channel c) =>
    '${c.id}|${c.name}|${c.category}|${c.streamUrl}|${c.logoUrl}|'
    '${c.catchupSupported}|${c.catchupDays}|${c.catchupSource}';

const String _sample = '''
#EXTM3U
#EXTINF:-1 tvg-id="c1" tvg-logo="http://logo/1.png" group-title="Sport",Canal Sport
http://stream/1.ts
#EXTGRP:Films
#EXTINF:-1,Film HD
http://stream/2.ts
http://stream/3.ts
#EXTVLCOPT:network-caching=1000
#EXTINF:-1 tvg-id="c4" catchup="default" catchup-days="7",Docs
http://stream/4.m3u8
pas-une-url-ignoree
''';

void main() {
  group('M3uParser.parseStreaming', () {
    test('produit EXACTEMENT le même résultat que parse()', () async {
      final List<Channel> sync =
          M3uParser.parse(_sample, playlistId: 9).channels;
      final List<Channel> streamed =
          (await M3uParser.parseStreaming(_sample, playlistId: 9)).channels;

      expect(streamed.length, sync.length);
      expect(
        streamed.map(_sig).toList(),
        sync.map(_sig).toList(),
      );
    });

    test('parse correctement les chaînes attendues', () async {
      final List<Channel> ch =
          (await M3uParser.parseStreaming(_sample, playlistId: 9)).channels;

      // 4 URLs valides ; la dernière ligne "pas-une-url" est ignorée.
      expect(ch.length, 4);
      expect(ch[0].id, 'c1');
      expect(ch[0].name, 'Canal Sport');
      expect(ch[0].category, 'Sport');
      expect(ch[0].logoUrl, 'http://logo/1.png');
      // EXTGRP s'applique à la chaîne #EXTINF suivante.
      expect(ch[1].name, 'Film HD');
      expect(ch[1].category, 'Films');
      // URL nue sans #EXTINF → nom + catégorie par défaut.
      expect(ch[2].name, 'Chaîne 3');
      expect(ch[2].category, 'Autres');
      // catchup détecté.
      expect(ch[3].id, 'c4');
      expect(ch[3].catchupSupported, isTrue);
      expect(ch[3].catchupDays, 7);
    });

    test('le découpage en lots (yieldEvery petit) ne perd rien', () async {
      // yieldEvery=1 force un await à chaque ligne : on vérifie que céder la
      // main entre les lignes ne casse pas l'accumulation d'état.
      final List<Channel> a =
          (await M3uParser.parseStreaming(_sample, playlistId: 1, yieldEvery: 1))
              .channels;
      final List<Channel> b =
          M3uParser.parse(_sample, playlistId: 1).channels;
      expect(a.map(_sig).toList(), b.map(_sig).toList());
    });

    test('contenu vide → aucune chaîne, pas d\'exception', () async {
      final result = await M3uParser.parseStreaming('', playlistId: 1);
      expect(result.channels, isEmpty);
    });
  });
}
