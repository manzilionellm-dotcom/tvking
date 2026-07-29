// =========================================================
//  tv_media_kit_import_guard_test.dart — GARDE DE BUILD TV
// =========================================================
//  CONTRAINTE CRITIQUE : le workflow build-tv.yml RETIRE media_kit du
//  pubspec avant compilation (l'APK TV lit exclusivement via ExoPlayer /
//  native_video_player). Si un fichier atteignable depuis lib/main_tv.dart
//  importe media_kit, le build TV casse — mais on ne le découvrait qu'en
//  CI, 20 minutes plus tard, ou pire : au moment de livrer.
//
//  Ce test calcule la fermeture transitive des imports/exports de
//  main_tv.dart (résolution package:tv_king/… + chemins relatifs, imports
//  conditionnels inclus par prudence) et échoue si media_kit y apparaît.
//  Audit 2026-07-29 : fermeture mesurée = ~194 fichiers, 0 media_kit —
//  ce test verrouille cet invariant pour la suite.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);
// Les branches d'un import conditionnel : if (dart.library.io) 'x.dart'
final RegExp _conditional = RegExp('''if\\s*\\([^)]*\\)\\s*['"]([^'"]+)['"]''');

void main() {
  test(
      'aucun import media_kit atteignable depuis lib/main_tv.dart '
      '(le build TV retire media_kit du pubspec)', () {
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'test à lancer depuis la racine du projet');

    String? resolve(String uri, String fromDir) {
      if (uri.startsWith('package:tv_king/')) {
        return 'lib/${uri.substring('package:tv_king/'.length)}';
      }
      if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
      // Chemin relatif
      final List<String> parts = <String>[...fromDir.split('/')];
      for (final String seg in uri.split('/')) {
        if (seg == '.' || seg.isEmpty) continue;
        if (seg == '..') {
          if (parts.isNotEmpty) parts.removeLast();
        } else {
          parts.add(seg);
        }
      }
      return parts.join('/');
    }

    final Set<String> visited = <String>{};
    final List<String> queue = <String>['lib/main_tv.dart'];
    final List<String> offenders = <String>[];

    while (queue.isNotEmpty) {
      final String path = queue.removeLast();
      if (!visited.add(path)) continue;
      final File f = File(path);
      if (!f.existsSync()) continue;
      final String src = f.readAsStringSync();

      // La détection porte sur les URI d'import réels, pas sur les
      // commentaires (features/tv contient des commentaires qui CITENT
      // l'interdiction media_kit).
      for (final RegExpMatch m in _directive.allMatches(src)) {
        final String uri = m.group(1)!;
        if (uri.startsWith('package:media_kit')) {
          offenders.add('$path → $uri');
          continue;
        }
        final String? next = resolve(uri, (f.parent.path).replaceAll('\\', '/'));
        if (next != null) queue.add(next);
        // Branches conditionnelles de la même directive (fin de ligne) :
        final int end = src.indexOf(';', m.start);
        if (end > m.start) {
          final String stmt = src.substring(m.start, end);
          for (final RegExpMatch c in _conditional.allMatches(stmt)) {
            final String curi = c.group(1)!;
            if (curi.startsWith('package:media_kit')) {
              offenders.add('$path → (conditionnel) $curi');
            } else {
              final String? cn =
                  resolve(curi, (f.parent.path).replaceAll('\\', '/'));
              if (cn != null) queue.add(cn);
            }
          }
        }
      }
    }

    expect(visited.length, greaterThan(100),
        reason: 'la fermeture de main_tv.dart doit couvrir l’app TV '
            '(sanity check : ${visited.length} fichiers visités)');
    expect(offenders, isEmpty,
        reason: 'media_kit est INTERDIT dans le build TV — imports fautifs :\n'
            '${offenders.join('\n')}');
  });
}
