// Test de composant sous Linux. Le fichier JSON ne contient ni URL
// fournisseur ni nom de chaîne. ZUNO_CATALOG_OUTPUT choisit la sortie.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

int _cpuTicks() {
  // Champs utime/stime de /proc/self/stat, après le nom entre parenthèses.
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

void main() {
  test('mesurer le parseur sur un catalogue synthétique', () {
    final rows = <Map<String, Object>>[];
    for (final size in [5000, 20000, 30000, 50000]) {
      final input = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < size; i++) {
        input.writeln('#EXTINF:-1 tvg-id="station$i" group-title="Groupe" '
            'tvg-logo="http://example.invalid/$i.png",Station $i');
        input.writeln('http://example.invalid/$i.ts');
      }
      final source = input.toString();
      for (var i = 0; i < 15; i++) {
        final cpu = _cpuTicks();
        final time = Stopwatch()..start();
        final parsed = M3uParser.parse(source, playlistId: 1);
        time.stop();
        final ticks = _cpuTicks() - cpu;
        expect(parsed.channels.length, size);
        if (i >= 3) {
          rows.add({
            'entries': size,
            'us': time.elapsedMicroseconds,
            'cpuTicks': ticks
          });
        }
      }
    }
    final invalid = List.filled(200000, 'ligne invalide').join('\n');
    final parsed = M3uParser.parse(
        '#EXTM3U\n$invalid\nhttp://example.invalid/ok.ts',
        playlistId: 1);
    expect(parsed.channels, hasLength(1));
    final result = {
      'samples': rows,
      'clkTck':
          Process.runSync('getconf', ['CLK_TCK']).stdout.toString().trim(),
      'warnings': parsed.warnings.length,
      'processMaxRssBytes': ProcessInfo.maxRss,
    };
    final output = Platform.environment['ZUNO_CATALOG_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(result));
  }, skip: !Platform.isLinux);
}
