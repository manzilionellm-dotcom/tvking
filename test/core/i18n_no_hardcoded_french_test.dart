// =========================================================
//  i18n_no_hardcoded_french_test.dart — Verrou anti-régression
// =========================================================
//  POURQUOI : le bug « changer de langue ne fait rien » est déjà
//  arrivé DEUX fois — les .arb étaient traduits mais les écrans
//  écrivaient leur texte en dur en français. Ce test échoue dès
//  qu'une chaîne française apparaît dans un « puits UI » (Text(…),
//  label:, title:, SnackBar…) au lieu de passer par context.l10n /
//  AppL10n.current.
//
//  Heuristique volontairement simple et robuste :
//    - on ne regarde que les lignes contenant un puits UI ;
//    - une chaîne littérale y est suspecte si elle contient une
//      lettre accentuée française (é è ê ë à â î ï ô û ù ç œ) —
//      un texte français en dur en contient presque toujours une ;
//    - les commentaires sont ignorés, ainsi qu'une liste courte
//      d'exceptions légitimes (noms natifs de langues, marques…).
//
//  Si ce test te bloque : N'AJOUTE PAS d'exception par réflexe.
//  La bonne correction est d'ajouter une clé dans lib/l10n/app_fr.arb
//  (+ les 7 autres langues) et d'utiliser context.l10n.maCle.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Fichiers où des chaînes accentuées en dur restent LÉGITIMES.
const Set<String> _allowedFiles = <String>{
  // Noms de langues affichés dans leur langue native (jamais traduits,
  // c'est voulu : chaque utilisateur doit reconnaître SA langue).
  'lib/core/i18n/locale_repository.dart',
};

// Puits UI : une chaîne littérale sur ces lignes est (très
// probablement) affichée à l'utilisateur.
final RegExp _uiSink = RegExp(
  r'\b(Text|SelectableText)\s*\(|SnackBar|AlertDialog|'
  r'\b(label|title|subtitle|hintText|labelText|helperText|tooltip|'
  r'semanticLabel|message|content|buttonText|hint)\s*:',
);

final RegExp _stringLiteral = RegExp(r"'((?:[^'\\]|\\.)*)'" '|"((?:[^"\\\\]|\\\\.)*)"');
final RegExp _frenchAccent = RegExp('[éèêëàâîïôûùçœÉÈÀÇ]');
final RegExp _lineComment = RegExp(r'//.*$');

void main() {
  test('aucun texte français en dur dans les puits UI (utilise context.l10n)',
      () {
    final List<String> violations = <String>[];

    final Iterable<File> dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !f.path.contains('l10n/generated'))
        .where((File f) => !_allowedFiles.contains(f.path.replaceAll('\\', '/')));

    for (final File file in dartFiles) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].replaceFirst(_lineComment, '');
        if (!_uiSink.hasMatch(line)) continue;
        for (final RegExpMatch m in _stringLiteral.allMatches(line)) {
          final String s = m.group(1) ?? m.group(2) ?? '';
          if (s.length < 3) continue;
          if (!_frenchAccent.hasMatch(s)) continue;
          violations.add('${file.path}:${i + 1}  « $s »');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Texte(s) français en dur dans un puits UI — passe par '
          'context.l10n (écrans) ou AppL10n.current (couche data), '
          'clé à ajouter dans lib/l10n/app_fr.arb + les 7 autres langues :\n'
          '${violations.join('\n')}',
    );
  });

  test('les 8 .arb ont exactement les mêmes clés que le template français',
      () {
    const List<String> langs = <String>[
      'fr', 'en', 'es', 'sv', 'da', 'nb', 'ar', 'sw',
    ];
    final Map<String, Set<String>> keysByLang = <String, Set<String>>{};
    for (final String lang in langs) {
      final String raw = File('lib/l10n/app_$lang.arb').readAsStringSync();
      // Extraction naïve mais suffisante des clés de premier niveau.
      final Iterable<RegExpMatch> matches =
          RegExp(r'^\s{0,2}"([^"@][^"]*)"\s*:', multiLine: true)
              .allMatches(raw);
      keysByLang[lang] =
          matches.map((RegExpMatch m) => m.group(1)!).toSet();
    }
    final Set<String> fr = keysByLang['fr']!;
    for (final String lang in langs.skip(1)) {
      final Set<String> missing = fr.difference(keysByLang[lang]!);
      final Set<String> extra = keysByLang[lang]!.difference(fr);
      expect(missing, isEmpty,
          reason: 'app_$lang.arb : clés manquantes vs FR : $missing');
      expect(extra, isEmpty,
          reason: 'app_$lang.arb : clés en trop vs FR : $extra');
    }
  });
}
