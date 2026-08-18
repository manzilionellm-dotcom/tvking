// =========================================================
//  tofu_exponents_test.dart — les carrés de la photo du 17/08
// =========================================================
//  Photo client (liste « Toutes les chaînes ») : « Prime ▯▯▯ »,
//  « FR| PRIME ▯▯▯ », « Prime: Automoto, LA Chaîne ▯▯▯ ».
//
//  Cause : les fournisseurs suffixent la qualité en EXPOSANTS (ᴴᴰ, ⁴ᴷ, ᶠᴴᴰ).
//  Unicode les classe LETTRES (\p{L}) → ils passaient la liste blanche
//  anti-tofu, et le chemin rapide de `_foldExotic` (seuil U+FF01) ne les
//  voyait même pas. Les polices des box ne les dessinent pas → carrés.
//
//  Ces tests verrouillent les deux moitiés du correctif : translittération
//  des exposants, et retrait des écritures non dessinables — SANS jamais
//  vider un nom ni abîmer un nom légitime.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/curation/title_curator.dart';

/// Un caractère est-il « sûr » pour une police de box ? On tolère le latin
/// étendu, le grec, le cyrillique, l'hébreu et l'arabe.
bool _renderable(int r) =>
    r < 0x0700 ||
    (r >= 0x0750 && r <= 0x077F) ||
    (r >= 0xFB50 && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF);

void main() {
  group('exposants → ASCII', () {
    test('la qualité en exposant devient lisible', () {
      expect(TitleCurator.stripUnrenderable('Prime ᴴᴰ'),
          'Prime HD');
      expect(TitleCurator.stripUnrenderable('Canal ⁴ᴷ'),
          'Canal 4K');
      expect(TitleCurator.stripUnrenderable('Sport ᶠᴴᴰ'),
          'Sport fHD');
    });

    test('les lettres cerclées et encadrées aussi', () {
      expect(TitleCurator.stripUnrenderable('ⒻⒶ Sport'), 'FA Sport');
      expect(TitleCurator.stripUnrenderable('\u{1F170}\u{1F171}'), 'AB');
    });

    test('les indices numériques aussi', () {
      expect(TitleCurator.stripUnrenderable('Ligue ₁'), 'Ligue 1');
    });
  });

  group('écritures non dessinables', () {
    test('un suffixe CJK est retiré, le nom latin survit', () {
      expect(TitleCurator.stripUnrenderable('Prime 中文').trim(),
          'Prime');
    });

    test('un nom ENTIÈREMENT CJK est conservé (jamais de ligne vide)', () {
      expect(TitleCurator.stripUnrenderable('中文').trim(),
          isNotEmpty);
    });

    test('l’arabe et le cyrillique restent intacts', () {
      expect(TitleCurator.stripUnrenderable('الجزيرة'),
          'الجزيرة');
      expect(TitleCurator.stripUnrenderable('Матч ТВ'),
          'Матч ТВ');
    });
  });

  group('non-régression : les vrais noms ne bougent pas', () {
    test('les noms de la photo restent identiques', () {
      for (final String n in <String>[
        'FR| PRIME',
        'Prime: Automoto, LA Chaîne',
        'Prime: 13eme RUE',
        'FR| FRANCE HEVC VIP',
        'FR| 24/7 BEIN CINEMA',
      ]) {
        expect(TitleCurator.stripUnrenderable(n), n, reason: n);
      }
    });

    test('curate() ne laisse aucun caractère non dessinable', () {
      const List<String> sales = <String>[
        'Prime ᴴᴰ',
        'FR| PRIME ᵁᴴᴰ',
        'Prime: AB1 ⁴ᴷ',
        'Canal+ 中文 Sport',
      ];
      for (final String s in sales) {
        final String out = TitleCurator.curate(s);
        expect(out.trim(), isNotEmpty, reason: s);
        for (final int r in out.runes) {
          expect(_renderable(r), isTrue,
              reason: 'U+${r.toRadixString(16).toUpperCase()} survit dans "$out" (source "$s")');
        }
      }
    });
  });
}
