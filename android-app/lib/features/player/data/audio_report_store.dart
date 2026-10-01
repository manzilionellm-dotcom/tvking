// =========================================================
//  audio_report_store.dart — Fichier local du diagnostic son
// =========================================================
//  Un JSON dans le dossier de l'app, plafonné par [AudioReportBook].
//  Pas de réseau. Si le disque refuse, on se tait : le lecteur continue.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/audio_report_book.dart';

class AudioReportStore {
  AudioReportStore._();
  static final AudioReportStore instance = AudioReportStore._();

  Future<File?> _file() async {
    try {
      final Directory dir = await getApplicationSupportDirectory();
      return File('${dir.path}/audio-diag.json');
    } catch (_) {
      return null;
    }
  }

  Future<AudioReportBook> load() async {
    try {
      final File? f = await _file();
      if (f == null || !await f.exists()) return AudioReportBook.empty;
      final Object? raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return AudioReportBook.empty;
      final Object? list = raw['entries'];
      if (list is! List) return AudioReportBook.empty;
      final List<AudioReportEntry> entries = <AudioReportEntry>[
        for (final Object? item in list)
          if (AudioReportEntry.fromJson(item) != null) AudioReportEntry.fromJson(item)!,
      ];
      return AudioReportBook(entries);
    } catch (_) {
      return AudioReportBook.empty;
    }
  }

  Future<void> record({
    required String channel,
    required String body,
    int? atMs,
  }) async {
    try {
      final AudioReportBook book = await load();
      final AudioReportBook next = book.add(
        channel: channel,
        body: body,
        atMs: atMs ?? DateTime.now().millisecondsSinceEpoch,
      );
      final File? f = await _file();
      if (f == null) return;
      await f.writeAsString(
        jsonEncode(<String, Object>{
          'entries': <Map<String, Object>>[
            for (final AudioReportEntry e in next.entries) e.toJson(),
          ],
        }),
        flush: true,
      );
    } catch (_) {
      // Le diagnostic ne doit jamais casser une lecture.
    }
  }

  Future<void> clear() async {
    try {
      final File? f = await _file();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }
}
