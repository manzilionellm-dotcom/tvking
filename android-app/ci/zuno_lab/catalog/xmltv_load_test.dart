import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/epg/data/epg_targets.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

String stamp(DateTime value) =>
    "${value.toUtc().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[-:T]'), '')} +0000";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deux variantes de 15 000 guides et lectures pendant republication', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    RepairFlags.debugReset();
    final dir = await Directory.systemTemp.createTemp('zuno-xmltv-');
    PlaylistDatabase.debugFilePath = '${dir.path}/guide.db';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final now = DateTime.now().toUtc();
    final times = [for (final minutes in [-30, 30, 90]) stamp(now.add(Duration(minutes: minutes)))];
    const guides = 15000;
    final map = buildEpgIdMap({
      for (var ch = 0; ch < guides * 2; ch++) 'xtream-$ch': 'guide-${ch ~/ 2}',
    });
    final xml = StringBuffer('<tv>');
    for (var id = 0; id < guides; id++) {
      for (var show = 0; show < 2; show++) {
        xml.write('<programme channel="guide-$id" start="${times[show]}" stop="${times[show+1]}">'
            '<title>Mire $id programme $show</title></programme>');
      }
    }
    xml.write('</tv>');
    final bytes = utf8.encode(xml.toString());
    final compressed = Uint8List.fromList(gzip.encode(bytes));
    var response = HttpStatus.ok;
    server.listen((req) async {
      req.response.statusCode = response;
      if (response == HttpStatus.ok) {
        req.response.headers.contentType = ContentType.binary;
        req.response.add(compressed);
      }
      await req.response.close();
    });
    final rows = <Map<String, Object?>>[];
    final repo = EpgRepository.instance;
    final url = 'http://127.0.0.1:${server.port}/guide';
    Future<void> measure(int pass) async {
      final clock = Stopwatch()..start();
      final timing = <int>[];
      final uiDelays = <int>[];
      var previous = clock.elapsedMilliseconds;
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final elapsed = clock.elapsedMilliseconds;
        uiDelays.add(elapsed - previous);
        previous = elapsed;
      });
      var reading = pass > 0;
      var invalid = 0;
      var i = 0;
      Future<void> checkPublished() async {
        while (reading) {
          final index = (i++ * 997) % (guides * 2);
          final read = Stopwatch()..start();
          final current = await repo.currentProgram('xtream-$index');
          timing.add(read.elapsedMicroseconds);
          if (current?.title != 'Mire ${index ~/ 2} programme 0') invalid++;
          await Future<void>.delayed(const Duration(milliseconds: 35));
        }
      }
      final reader = checkPublished();
      late final int written;
      try {
        written = await repo.downloadAndImport(url: url, channelIdMap: map);
      } finally {
        reading = false;
        timer.cancel();
      }
      final elapsed = clock.elapsedMilliseconds;
      await reader;
      expect(written, guides * 4);
      expect(await repo.totalCount(), guides * 4);
      expect(invalid, 0);
      rows.add({'pass': pass, 'import_ms': elapsed, 'rows': written,
        'published_reads_us': timing, 'wrong_or_blank_programs': invalid,
        'main_isolate_heartbeat_intervals_ms': uiDelays});
    }
    try {
      for (var pass = 0; pass < 3; pass++) { await measure(pass); }
      response = HttpStatus.serviceUnavailable;
      await expectLater(repo.downloadAndImport(url: url, channelIdMap: map), throwsA(anything));
      expect(await repo.totalCount(), guides * 4);
      expect((await repo.currentProgram('xtream-29998'))?.title, 'Mire 14999 programme 0');
      expect((await repo.currentProgram('xtream-29999'))?.title, 'Mire 14999 programme 0');
      final db = await PlaylistDatabase.instance.database;
      final query = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM epg_programs '
          'WHERE channel_id=? AND start_time<=? AND stop_time>? LIMIT 1',
          ['xtream-123', now.millisecondsSinceEpoch, now.millisecondsSinceEpoch]);
      final result = {'catalogue_channels': guides * 2, 'guide_ids': guides, 'gzip_bytes': compressed.length,
        'xml_bytes': bytes.length, 'series': rows, 'plan': query,
        'rows_after_failed_refresh': await repo.totalCount(), 'final_two_variants_same_program': true};
      final out = Platform.environment['ZUNO_EPG_RESULT'];
      if (out != null) await File(out).writeAsString(jsonEncode(result));
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
