import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  const params = <String, Map<String, String>>{
    'catalogLimitTitle': {},
    'catalogLimitSummary': {
      'stored': 'int',
      'read': 'int',
      'loaded': 'int',
      'limit': 'int',
    },
    'catalogLimitPreserved': {},
    'catalogLimitSource': {
      'name': 'String',
      'stored': 'int',
      'read': 'int',
      'loaded': 'int',
    },
    'catalogLimitImport': {
      'name': 'String',
      'total': 'int',
      'retained': 'int',
      'skipped': 'int',
    },
    'catalogLimitKids': {},
    'catalogLimitUnnamed': {'id': 'int'},
    'catalogLimitSources': {'sources': 'String'},
  };
  const languages = [
    'fr',
    'en',
    'de',
    'es',
    'pt',
    'it',
    'nl',
    'sv',
    'nb',
    'da',
    'ru',
    'tr',
    'ar',
    'hi',
    'zh',
    'sw',
    'so',
  ];
  for (final language in languages) {
    test('L1-04 ARB $language : tous les paramètres sont nommés et typés', () {
      final arb = jsonDecode(
        File('lib/l10n/app_$language.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final entry in params.entries) {
        final message = arb[entry.key] as String;
        expect(message, isNotEmpty);
        final actual = RegExp(r'\{(\w+)\}')
            .allMatches(message)
            .map((match) => match.group(1))
            .toSet();
        expect(actual, entry.value.keys.toSet(), reason: entry.key);
        if (entry.value.isEmpty) continue;
        final metadata = arb['@${entry.key}']['placeholders'] as Map;
        expect(metadata.keys.toSet(), entry.value.keys.toSet());
        for (final placeholder in entry.value.entries) {
          expect(metadata[placeholder.key]['type'], placeholder.value);
        }
      }
    });
  }
  test(
    'les 17 générateurs rendent les messages sans valeur manquante',
    () async {
      expect(
        AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
        containsAll(languages),
      );
      for (final language in languages) {
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        expect(
          l10n.catalogLimitSummary(100000, 50000, 49999, 50000),
          allOf(contains('100000'), contains('50000'), contains('49999')),
        );
        expect(
          l10n.catalogLimitSource('Fixture', 25000, 0, 0),
          contains('Fixture'),
        );
        expect(
          l10n.catalogLimitImport('Fixture', 50003, 50000, 3),
          allOf(
            contains('Fixture'),
            contains('50003'),
            contains('50000'),
            contains('3'),
          ),
        );
        expect(l10n.catalogLimitUnnamed(4), contains('4'));
        expect(l10n.catalogLimitSources('Fixture'), contains('Fixture'));
        expect(l10n.catalogLimitKids, isNotEmpty);
      }
    },
  );
}
