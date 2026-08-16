// =========================================================
//  vod_source_tag_test.dart — Étiquettes de source VOD
// =========================================================
//  Photo client (16/08) : TOUS les films de l'accueil Cinéma s'appelaient
//  « 4k-nf - To the Max », « 4k-nf - Disenchantment »… Le fournisseur
//  préfixe ses titres VOD avec la qualité et la plateforme d'origine.
//
//  Ces tests verrouillent LES DEUX côtés de la règle :
//   • les vraies étiquettes sont retirées ;
//   • les VRAIS titres ne sont JAMAIS amputés (« Max Payne », « Mad Max »,
//     « Disney Classics »…). C'est le risque réel d'une règle trop large.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/curation/title_curator.dart';

void main() {
  group('Étiquettes de source retirées', () {
    for (final String raw in <String>[
      '4k-nf - To the Max',
      '4K-NF - Disenchantment',
      'UHD_AMZN | The Boys',
      'fhd-dsnp : Loki',
      'NF - Stranger Things',
      'hbo — Succession',
    ]) {
      test(raw, () {
        final String out = TitleCurator.curate(raw);
        expect(out.toLowerCase(), isNot(startsWith('4k')));
        expect(out.toLowerCase(), isNot(startsWith('nf ')));
        expect(out.toLowerCase(), isNot(startsWith('uhd')));
        expect(out.toLowerCase(), isNot(startsWith('fhd')));
        expect(out.trim(), isNotEmpty);
      });
    }
  });

  group('Vrais titres PRÉSERVÉS (anti-amputation)', () {
    const Map<String, String> keep = <String, String>{
      'Max Payne': 'Max',
      'Mad Max - Fury Road': 'Mad Max',
      'Stanley Kubrick Collection': 'Stanley',
      'Disney Classics': 'Disney',
      'Nform - Documentaire': 'Nform',
    };
    keep.forEach((String raw, String mustStartWith) {
      test(raw, () {
        expect(TitleCurator.curate(raw), startsWith(mustStartWith));
      });
    });
  });

  test('une catégorie décorée reste lisible après curation', () {
    final String out = TitleCurator.curateCategory('NETFLIX MOVIES 〓〓 4K');
    expect(out, contains('NETFLIX'));
    expect(out, isNot(contains('〓')));
  });
}
