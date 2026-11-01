// Les symboles somalis manquent à la version d'intl du SDK. On les fournit
// localement : pas de traduction réseau et pas de changement du contenu client.
// Référence des noms : https://unicode.org/cldr/charts/49/summary/so.html
import 'dart:async';

import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbol_data_local.dart' as intl_data;
import 'package:intl/date_symbols.dart';
import 'package:intl/number_symbols.dart';
import 'package:intl/number_symbols_data.dart';

const somaliMonths = <String>[
  'Jannaayo',
  'Febraayo',
  'Maarso',
  'Abriil',
  'Maajo',
  'Juun',
  'Luulyo',
  'Agoosto',
  'Sebtembar',
  'Oktoobar',
  'Nofeembar',
  'Diseembar',
];
const somaliWeekdays = <String>[
  'Axad',
  'Isniin',
  'Talaado',
  'Arbaco',
  'Khamiis',
  'Jimce',
  'Sabti',
];
bool _initialized = false;
void initializeSomaliFormats() {
  if (_initialized) return;
  // Charger d'abord les données SDK préserve les seize autres langues.
  // L’API installe les tables immédiatement ; son Future ne transporte
  // aucune opération IO. Ne pas partager un Future entre les arbres Flutter.
  unawaited(intl_data.initializeDateFormatting());
  final shortMonths = somaliMonths.map((v) => v.substring(0, 3)).toList();
  final shortDays = somaliWeekdays.map((v) => v.substring(0, 3)).toList();
  final symbols = DateSymbols(
    NAME: 'so',
    ERAS: const ['CH', 'CD'],
    ERANAMES: const ['Ciise hortiis', 'Ciise dabadii'],
    NARROWMONTHS: somaliMonths.map((v) => v[0]).toList(),
    STANDALONENARROWMONTHS: somaliMonths.map((v) => v[0]).toList(),
    MONTHS: somaliMonths,
    STANDALONEMONTHS: somaliMonths,
    SHORTMONTHS: shortMonths,
    STANDALONESHORTMONTHS: shortMonths,
    WEEKDAYS: somaliWeekdays,
    STANDALONEWEEKDAYS: somaliWeekdays,
    SHORTWEEKDAYS: shortDays,
    STANDALONESHORTWEEKDAYS: shortDays,
    NARROWWEEKDAYS: const ['A', 'I', 'T', 'A', 'K', 'J', 'S'],
    STANDALONENARROWWEEKDAYS: const ['A', 'I', 'T', 'A', 'K', 'J', 'S'],
    SHORTQUARTERS: const ['R1', 'R2', 'R3', 'R4'],
    QUARTERS: const [
      'Rubuca 1aad',
      'Rubuca 2aad',
      'Rubuca 3aad',
      'Rubuca 4aad'
    ],
    AMPMS: const ['GH', 'GD'],
    DATEFORMATS: const ['EEEE, d MMMM y', 'd MMMM y', 'd MMM y', 'dd/MM/y'],
    TIMEFORMATS: const ['HH:mm:ss zzzz', 'HH:mm:ss z', 'HH:mm:ss', 'HH:mm'],
    DATETIMEFORMATS: const ['{1} {0}', '{1} {0}', '{1} {0}', '{1} {0}'],
    FIRSTDAYOFWEEK: 5,
    WEEKENDRANGE: const [4, 5],
    FIRSTWEEKCUTOFFDAY: 5,
  );
  initializeDateFormattingCustom(locale: 'so', symbols: symbols, patterns: {
    'd': 'd',
    'E': 'ccc',
    'EEEE': 'cccc',
    'LLL': 'LLL',
    'LLLL': 'LLLL',
    'M': 'L',
    'Md': 'dd/MM',
    'MEd': 'EEE, dd/MM',
    'MMM': 'LLL',
    'MMMd': 'd MMM',
    'MMMEd': 'EEE, d MMM',
    'MMMM': 'LLLL',
    'MMMMd': 'd MMMM',
    'MMMMEEEEd': 'EEEE, d MMMM',
    'y': 'y',
    'yM': 'MM/y',
    'yMd': 'dd/MM/y',
    'yMEd': 'EEE, dd/MM/y',
    'yMMM': 'MMM y',
    'yMMMd': 'd MMM y',
    'yMMMEd': 'EEE, d MMM y',
    'yMMMM': 'MMMM y',
    'yMMMMd': 'd MMMM y',
    'yMMMMEEEEd': 'EEEE, d MMMM y',
    'yQQQ': 'QQQ y',
    'yQQQQ': 'QQQQ y',
    'H': 'HH',
    'Hm': 'HH:mm',
    'Hms': 'HH:mm:ss',
    'j': 'HH',
    'jm': 'HH:mm',
    'jms': 'HH:mm:ss',
    'jmv': 'HH:mm v',
    'jmz': 'HH:mm z',
    'jv': 'HH v',
    'jz': 'HH z',
    'ms': 'mm:ss',
    's': 'ss',
  });
  numberFormatSymbols['so'] = const NumberSymbols(
    NAME: 'so',
    DECIMAL_SEP: '.',
    GROUP_SEP: ',',
    PERCENT: '%',
    ZERO_DIGIT: '0',
    PLUS_SIGN: '+',
    MINUS_SIGN: '-',
    EXP_SYMBOL: 'E',
    PERMILL: '‰',
    INFINITY: '∞',
    NAN: 'NaN',
    DECIMAL_PATTERN: '#,##0.###',
    SCIENTIFIC_PATTERN: '#E0',
    PERCENT_PATTERN: '#,##0%',
    CURRENCY_PATTERN: '¤#,##0.00',
    DEF_CURRENCY_CODE: 'SOS',
  );
  _initialized = true;
}
