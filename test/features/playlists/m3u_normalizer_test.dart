// =========================================================
//  m3u_normalizer_test.dart — la playlist propre ET la sale
// =========================================================
//  Ce qu'on verrouille ici (16/09/2026) :
//
//   1. Une playlist PROPRE traverse sans être abîmée.
//   2. Une playlist SALE — BOM, espaces, `\r\n`, pas de `#EXTM3U` —
//      donne EXACTEMENT les mêmes chaînes que la propre. C'est le cœur
//      du correctif : le client ne doit pas voir la différence.
//   3. Une réponse qui n'est PAS une playlist (page d'erreur du
//      fournisseur servie en HTTP 200 — le cas terrain n°1) est nommée,
//      pas avalée en silence.
//   4. On ne recopie pas le fichier : l'examen rend un OFFSET.
//      Un test le prouve sur une playlist volumineuse.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_normalizer.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

/// LA PROPRE — telle qu'un bon panneau la sert.
const String kPlaylistPropre = '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="tf1.fr" tvg-name="TF1" group-title="France",TF1\n'
    'http://exemple.tv:8080/live/u/p/1.ts\n'
    '#EXTINF:-1 tvg-id="fr2.fr" tvg-name="France 2" group-title="France",France 2\n'
    'http://exemple.tv:8080/live/u/p/2.ts\n';

/// LA SALE — le même contenu, passé par un export Windows et un
/// copier-coller. BOM en tête, ligne vide, `#EXTM3U` absent, fins de
/// ligne `\r\n`, espaces parasites en fin de ligne.
const String kPlaylistSale = '﻿'
    '  \r\n'
    '#EXTINF:-1 tvg-id="tf1.fr" tvg-name="TF1" group-title="France",TF1  \r\n'
    'http://exemple.tv:8080/live/u/p/1.ts  \r\n'
    '#EXTINF:-1 tvg-id="fr2.fr" tvg-name="France 2" group-title="France",France 2\r\n'
    'http://exemple.tv:8080/live/u/p/2.ts\r\n';

void main() {
  group('examen — playlist propre', () {
    test('traverse intacte, en-tête reconnu, rien à réparer', () {
      final VerdictM3u v = examinerM3u(kPlaylistPropre);
      expect(v.exploitable, isTrue);
      expect(v.entete, isTrue);
      expect(v.offset, 0, reason: 'rien à sauter en tête');
      expect(v.corrections, isEmpty);
    });
  });

  group('examen — playlist sale', () {
    test('BOM et blancs de tête sautés, en-tête forcé, tout est dit', () {
      final VerdictM3u v = examinerM3u(kPlaylistSale);
      expect(v.exploitable, isTrue,
          reason: 'sale ne veut pas dire inutilisable');
      expect(v.entete, isFalse);
      expect(v.offset, greaterThan(0),
          reason: 'le BOM et la ligne vide sont sautés par OFFSET');
      // Chaque réparation est NOMMÉE : c'est ce qui s'affiche dans le
      // détail d'import, et ce que le support peut lire au téléphone.
      expect(v.corrections.join(' '), contains('BOM'));
      expect(v.corrections.join(' '), contains('#EXTM3U'));
    });

    test('deux BOM empilés (fichier converti deux fois) passent aussi', () {
      final VerdictM3u v = examinerM3u('﻿﻿$kPlaylistPropre');
      expect(v.exploitable, isTrue);
      expect(v.entete, isTrue);
      expect(v.offset, 2);
    });
  });

  group('LE TEST QUI COMPTE — propre et sale donnent la MÊME chose', () {
    test('mêmes chaînes, mêmes noms, mêmes URLs', () {
      final M3uParseResult propre =
          M3uParser.parse(kPlaylistPropre, playlistId: 1);
      final M3uParseResult sale = M3uParser.parse(kPlaylistSale, playlistId: 1);

      expect(propre.channels.length, 2);
      expect(sale.channels.length, propre.channels.length,
          reason: 'le client ne doit PAS voir la différence');
      for (int i = 0; i < propre.channels.length; i++) {
        expect(sale.channels[i].name, propre.channels[i].name);
        expect(sale.channels[i].streamUrl, propre.channels[i].streamUrl,
            reason: 'un \\r resté collé à l\'URL = écran noir garanti');
      }
      expect(propre.raisonInvalide, isNull);
      expect(sale.raisonInvalide, isNull);
    });

    test('aucune URL ne traîne de \\r — la cause classique de l\'écran noir',
        () {
      final M3uParseResult sale = M3uParser.parse(kPlaylistSale, playlistId: 1);
      for (final c in sale.channels) {
        expect(c.streamUrl.contains('\r'), isFalse);
        expect(c.streamUrl.trim(), c.streamUrl);
      }
    });
  });

  group('ce qui n\'est PAS une playlist est NOMMÉ, jamais avalé', () {
    test('page HTML d\'erreur servie en HTTP 200 (le cas terrain n°1)', () {
      const String html = '<!DOCTYPE html>\n<html><body>'
          '<h1>Line expired</h1></body></html>';
      final VerdictM3u v = examinerM3u(html);
      expect(v.exploitable, isFalse);
      expect(v.raison, RaisonM3uInvalide.pageWeb);
      expect(messageM3uInvalide(v.raison!), contains('page web'));
    });

    test('la raison remonte jusqu\'au résultat de parsing', () {
      final M3uParseResult r =
          M3uParser.parse('<html><body>nope</body></html>', playlistId: 1);
      expect(r.channels, isEmpty);
      expect(r.raisonInvalide, RaisonM3uInvalide.pageWeb,
          reason: 'sans ça, l\'appelant ne peut dire que « 0 chaîne »');
      expect(r.warnings.join(' '), contains('page web'));
    });

    test('réponse JSON d\'API (identifiants refusés)', () {
      final VerdictM3u v =
          examinerM3u('{"user_info":{"auth":0,"message":"Invalid"}}');
      expect(v.raison, RaisonM3uInvalide.reponseApi);
    });

    test('contenu vide, ou un BOM tout seul', () {
      expect(examinerM3u('').raison, RaisonM3uInvalide.vide);
      expect(examinerM3u('﻿').raison, RaisonM3uInvalide.vide);
      expect(examinerM3u('   \r\n  \n').raison, RaisonM3uInvalide.vide);
    });

    test('du texte qui n\'est ni playlist ni document connu', () {
      expect(examinerM3u('bonjour, ceci est un fichier texte').raison,
          RaisonM3uInvalide.pasUnePlaylist);
    });
  });

  group('on ne refuse PAS ce qui pourrait marcher', () {
    //  Le faux positif est l'erreur CHÈRE : elle prive un client payant
    //  d'une liste qui fonctionnait. Ces cas doivent passer.
    test('liste d\'URLs nues, sans #EXTM3U ni #EXTINF', () {
      const String nue = 'http://exemple.tv:8080/live/u/p/1.ts\n'
          'http://exemple.tv:8080/live/u/p/2.ts\n';
      final VerdictM3u v = examinerM3u(nue);
      expect(v.exploitable, isTrue);
      expect(v.corrections.join(' '), contains('URLs nues'));
    });

    test('un nom de chaîne contenant un chevron ne fait pas « page web »',
        () {
      const String piege = '#EXTM3U\n'
          '#EXTINF:-1,TF1 <HD>\n'
          'http://exemple.tv/1.ts\n';
      final VerdictM3u v = examinerM3u(piege);
      expect(v.exploitable, isTrue,
          reason: 'on cherche la playlist AVANT de crier au HTML');
    });
  });

  group('on ne recopie pas le fichier', () {
    test('l\'examen rend un offset, même sur une grosse playlist', () {
      final StringBuffer b = StringBuffer('﻿\n');
      for (int i = 0; i < 20000; i++) {
        b.writeln('#EXTINF:-1,Chaine $i');
        b.writeln('http://exemple.tv/$i.ts');
      }
      final String gros = b.toString();
      final VerdictM3u v = examinerM3u(gros);
      expect(v.exploitable, isTrue);
      // La preuve : l'offset saute juste le BOM + le saut de ligne. Si un
      // jour quelqu'un remplace l'examen par un `replaceAll`, l'offset
      // retombera à 0 et ce test tombera — c'est son rôle.
      expect(v.offset, 2);
      // Et le parsing part bien de là.
      final M3uParseResult r = M3uParser.parse(gros, playlistId: 1);
      expect(r.channels.length, 20000);
      expect(r.channels.first.name, 'Chaine 0');
    });
  });
}
