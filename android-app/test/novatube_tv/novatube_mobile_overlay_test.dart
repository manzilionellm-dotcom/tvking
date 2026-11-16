// =========================================================
//  Contrat avec la chaîne de livraison du téléphone 7 MOTION
// =========================================================
//  ci/mobile/prepare_panel_controls.py et ci/mobile/mobile_controls_options.py
//  recopient des fichiers de cette app dans l'arbre du TÉLÉPHONE, figé à un
//  autre commit, qui ne contient pas l'édition NovaTube TV.
//
//  • Un fichier recopié EN ENTIER ne doit importer aucun fichier propre à
//    NovaTube : sinon l'analyse et la construction du téléphone échouent
//    (vu en CI le 16/11/2026 : « Target of URI doesn't exist »). Ces
//    fichiers relisent le define NOVATUBE_TV eux-mêmes, sans import.
//  • Deux fichiers ne sont recopiés que PAR SECTION (device_identity.dart,
//    subscription_backend.dart) : leurs imports restent côté TV, mais la
//    section recopiée ne doit pas parler de NovaTube.
//
//  Les listes sont lues dans les scripts eux-mêmes : un fichier ajouté plus
//  tard à la copie est contrôlé sans modifier ce test.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Import d'un fichier qui n'existe que dans l'édition NovaTube TV.
final RegExp _novatubeImport = RegExp(
  r'''^import\s+['"][^'"]*(novatube_tv_edition|novatube_identity|novatube_atlas|tv_novatube_)[^'"]*['"]''',
  multiLine: true,
);

/// Copies « telles quelles » : boucles `for path in [...]` suivies de
/// `files[path] = src(path)` ou `files[path] = (source / path).read_text()`.
final RegExp _asIsLoop = RegExp(
  r'for path in \[(.*?)\]:\s*files\[path\] = (?:src\(path\)|\(source / path\)\.read_text\(\))',
  dotAll: true,
);

/// Fichiers recopiés par section, avec les MÊMES ancres que
/// ci/mobile/prepare_panel_controls.py (`replace_section` / `section`).
const Map<String, List<String>> _sections = <String, List<String>>{
  'lib/features/device/data/device_identity.dart': <String>[
    '  Future<Map<String, String>> deviceInfo() async {',
    '  /// Régénère un nouveau MAC',
  ],
  'lib/features/subscription/data/subscription_backend.dart': <String>[
    "        'build': info['build'] ?? '',\n",
    "        'androidId': androidId,",
  ],
};

/// Fichiers partagés qui gardent une garde NovaTube sans import.
const List<String> _localGuards = <String>[
  'lib/features/feedback/data/feedback_repository.dart',
  'lib/features/playlists/data/default_servers.dart',
  'lib/features/theme/data/remote_theme_repository.dart',
];

Set<String> _copiedAsIs() => <String>{
      for (final String script in <String>[
        'ci/mobile/prepare_panel_controls.py',
        'ci/mobile/mobile_controls_options.py',
      ])
        for (final RegExpMatch loop
            in _asIsLoop.allMatches(File(script).readAsStringSync()))
          for (final RegExpMatch path in RegExp(r"'((?:lib|test)/[^']+\.dart)'")
              .allMatches(loop.group(1)!))
            path.group(1)!,
    };

void main() {
  test('les fichiers recopiés tels quels vers le téléphone sont bien lus', () {
    // Garde-fou du test lui-même : si le format des scripts change, on
    // échoue ici au lieu de ne plus rien contrôler.
    expect(_copiedAsIs(), containsAll(_localGuards));
  });

  test("aucun fichier recopié tel quel n'importe un fichier propre à NovaTube",
      () {
    final List<String> fautifs = <String>[
      for (final String path in _copiedAsIs())
        if (File(path).existsSync() &&
            _novatubeImport.hasMatch(File(path).readAsStringSync()))
          path,
    ];
    expect(fautifs, isEmpty,
        reason: "l'arbre du téléphone 7 MOTION ne contient pas ces fichiers");
  });

  test('les sections recopiées ne parlent pas de NovaTube', () {
    _sections.forEach((String path, List<String> ancres) {
      final String text = File(path).readAsStringSync();
      final int debut = text.indexOf(ancres[0]);
      expect(debut, greaterThanOrEqualTo(0), reason: '$path : début absent');
      final int fin = text.indexOf(ancres[1], debut + 1);
      expect(fin, greaterThan(debut), reason: '$path : fin absente');
      expect(text.substring(debut, fin).toLowerCase(),
          isNot(contains('novatube')),
          reason: path);
    });
  });

  test('les gardes locales lisent le même define que novatube_tv_edition', () {
    expect(File('lib/core/app/novatube_tv_edition.dart').readAsStringSync(),
        contains("const bool kNovatubeTv = bool.fromEnvironment('NOVATUBE_TV');"));
    for (final String path in _localGuards) {
      expect(
          File(path).readAsStringSync(),
          contains(
              "const bool _kNovatubeTv = bool.fromEnvironment('NOVATUBE_TV');"),
          reason: path);
    }
  });
}
