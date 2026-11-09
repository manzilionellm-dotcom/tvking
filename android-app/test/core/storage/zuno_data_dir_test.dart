import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/storage/zuno_data_dir.dart';

void main() {
  test('legacy Documents database is copied once, old file kept', () async {
    final Directory root = Directory.systemTemp.createTempSync('zuno-mig');
    try {
      final Directory docs = Directory('${root.path}/Documents')..createSync();
      final Directory app = Directory('${root.path}/AppData/Zuno/Zuno');
      File('${docs.path}/tv_king.db').writeAsStringSync('base');
      File('${docs.path}/tv_king.db-wal').writeAsStringSync('wal');
      await migrateWindowsDocumentsFile('tv_king.db', app,
          legacyDir: () async => docs);
      expect(File('${app.path}/tv_king.db').readAsStringSync(), 'base');
      expect(File('${app.path}/tv_king.db-wal').readAsStringSync(), 'wal');
      expect(File('${docs.path}/tv_king.db').existsSync(), isTrue);
      // Deuxième démarrage : la base déjà migrée n'est jamais écrasée.
      File('${app.path}/tv_king.db').writeAsStringSync('nouvelle');
      await migrateWindowsDocumentsFile('tv_king.db', app,
          legacyDir: () async => docs);
      expect(File('${app.path}/tv_king.db').readAsStringSync(), 'nouvelle');
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('unreadable legacy folder never throws', () async {
    final Directory root = Directory.systemTemp.createTempSync('zuno-mig');
    try {
      await migrateWindowsDocumentsFile('tv_king.db', root,
          legacyDir: () async => throw const FileSystemException('denied'));
      expect(File('${root.path}/tv_king.db').existsSync(), isFalse);
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
