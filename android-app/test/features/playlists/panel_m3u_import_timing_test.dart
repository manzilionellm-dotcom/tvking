// =========================================================
//  panel_m3u_import_timing_test.dart — Combien de temps dure
//  l'IMPORT d'une liste M3U envoyée par le panel ?
// =========================================================
//  Maillon 4 de la chaîne « clic dans le panel → chaînes sur la
//  TV » : téléchargement (ici instantané, client HTTP simulé),
//  analyse dans un isolate, insertion SQLite par lots de 1 000.
//  Le test mesure le vrai code (PlaylistRepository.addM3uPlaylist)
//  sur une liste synthétique, et imprime `MESURE …` comme les
//  autres tests chronométrés du dépôt.
//
//  Ce chiffre est celui de la machine de test, pas d'une box à
//  1 Go : il donne l'ORDRE DE GRANDEUR et le rapport entre les
//  tailles. Sur la box, la ligne de boîte noire
//  « liste M3U du panel chargée en N s (X chaînes) » donne le réel.
//  Aucune adresse de flux réelle : tout est en 127.0.0.1.
// =========================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

/// Liste M3U « façon fournisseur » : attributs tvg-*, groupes, une
/// adresse par chaîne. ~140 octets par chaîne, comme en vrai.
Uint8List _m3u(int channels) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < channels; i++) {
    sb
      ..write('#EXTINF:-1 tvg-id="ch$i.fr" tvg-name="Chaîne $i" ')
      ..write('tvg-logo="http://127.0.0.1/logo/$i.png" ')
      ..write('group-title="Groupe ${i % 40}",Chaîne $i\n')
      ..write('http://127.0.0.1/mesure/$i.ts\n');
  }
  return Uint8List.fromList(sb.toString().codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // La lecture fusionnée (TV) consulte la marque courante.
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-import-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('import M3U du panel : 5 000, 20 000 et 50 000 chaînes, chronométré',
      () async {
    final Map<int, Uint8List> bodies = <int, Uint8List>{
      5000: _m3u(5000),
      20000: _m3u(20000),
      50000: _m3u(50000),
    };
    final http.Client client = MockClient((http.Request r) async {
      final int n = int.parse(r.url.pathSegments.last.split('.').first);
      return http.Response.bytes(bodies[n]!, 200);
    });

    for (final MapEntry<int, Uint8List> e in bodies.entries) {
      final Stopwatch sw = Stopwatch()..start();
      final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
        name: 'Mesure ${e.key}',
        url: 'http://127.0.0.1/mesure/${e.key}.m3u',
        httpClient: client,
      );
      sw.stop();
      // Format repris par les autres tests chronométrés (grep MESURE).
      // ignore: avoid_print
      print('MESURE import_m3u_${e.key}_chaines_ms=${sw.elapsedMilliseconds} '
          'octets=${e.value.length}');
      expect(saved.channelCount, e.key,
          reason: 'toutes les chaînes de la liste sont insérées');
      // Garde-fou large : une régression ×10 du parser ou des lots
      // SQLite se verrait ici, pas chez un client.
      expect(sw.elapsed, lessThan(const Duration(seconds: 120)),
          reason: '${e.key} chaînes en ${sw.elapsedMilliseconds} ms');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
