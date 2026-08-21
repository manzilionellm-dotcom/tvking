// =========================================================
//  prettify_category_pro_test.dart — Catégories « pro / VIP »
// =========================================================
//  Photo client (box réelle, 2026-08) : la liste des groupes affichait
//  « #### FRANCE HEVC VIP #### » et « #### PRIME ▓▓ 60fps #### » tels
//  quels — bandes de #, blocs pleins ▓ et balises techniques compris.
//  Depuis, `ChannelClassifier.prettifyCategory` passe par la curation
//  complète du TitleCurator : ces tests verrouillent le contrat.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/curation/title_curator.dart';
import 'package:tv_king/features/channels/domain/channel_genre.dart';

void main() {
  group('prettifyCategory — rendu professionnel', () {
    test('bandes #### + balises qualité/VIP → libellé propre', () {
      expect(ChannelClassifier.prettifyCategory('#### FRANCE HEVC VIP ####'),
          'France');
    });

    test('blocs pleins ▓ (photo client) sautent aussi', () {
      expect(ChannelClassifier.prettifyCategory('#### PRIME ▓▓ 60fps ####'),
          'Prime');
    });

    test('libellé déjà propre : inchangé (Title Case respecté)', () {
      expect(ChannelClassifier.prettifyCategory('Documentaires'),
          'Documentaires');
    });

    test('acronymes préservés (jamais « Tf1 »)', () {
      expect(ChannelClassifier.prettifyCategory('== TF1 HD =='), 'TF1');
    });

    test('vidé par le nettoyage → « Autres » (jamais une ligne vide)', () {
      expect(ChannelClassifier.prettifyCategory('#### ▓▓▓ ####'), 'Autres');
    });

    test('pictogramme ▦ (photo client 21/08) et écriture exotique sautent',
        () {
      // Le glyphe 3×3 qui suivait chaque nom (« PRIME: ACTION MAX ▦ ») et
      // une lettre tifinagh (\p{L} hors écritures des box) : tous deux
      // doivent disparaître du nom curé.
      // (« MAX » reste en capitales : règle des sigles ≤ 3 lettres.)
      expect(TitleCurator.curate('PRIME: ACTION MAX ▦'), 'Prime: Action MAX');
      expect(TitleCurator.curate('CANAL ⵣ PLUS'), 'Canal');
    });

    test('deux décorations différentes FUSIONNENT en un seul groupe', () {
      final String a =
          ChannelClassifier.prettifyCategory('## SPORT FHD ##');
      final String b =
          ChannelClassifier.prettifyCategory('★ SPORT ★');
      expect(a, b);
    });
  });
}
