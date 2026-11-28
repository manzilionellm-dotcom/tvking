import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/recordings/data/recording_repository.dart';
import 'package:tv_king/features/recordings/domain/recording.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'la copie locale suit la clôture, avec une seule publication par capture',
      () async {
    final temp = await Directory.systemTemp.createTemp('novatube-video-locale');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PlaylistDatabase.debugFilePath = '${temp.path}/essai.db';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.manzilionellm.tvking/gallery');
    final attempts = <MethodCall>[];
    var refuse = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      attempts.add(call);
      if (refuse) throw PlatformException(code: 'PERMISSION_DENIED');
      return true;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await temp.delete(recursive: true);
    });

    final repo = RecordingRepository.instance;
    final source = await File('${temp.path}/test.ts').writeAsBytes([1, 2, 3]);
    final recording = await repo.startRecording(
      channelId: 'fixture',
      channelName: 'Mire',
      filePath: source.path,
    );
    expect(attempts, isEmpty);

    const enabled = bool.fromEnvironment('NOVATUBE_TV') &&
        bool.fromEnvironment('NOVATUBE_LOCAL_RECORDINGS');
    Future<Recording> when(bool Function(Recording) predicate) {
      final match = repo.current.where((r) => r.id == recording.id).first;
      if (predicate(match)) return Future.value(match);
      return repo.stream
          .map((rows) => rows.firstWhere((r) => r.id == recording.id))
          .firstWhere(predicate)
          .timeout(const Duration(seconds: 5));
    }

    await Future.wait(
        [repo.finishRecording(recording), repo.finishRecording(recording)]);
    if (!enabled) {
      expect(attempts, isEmpty);
      expect(repo.current.single.deviceCopyStatus, isNull);
      return;
    }
    final failed = await when((r) => r.deviceCopyFailed);
    expect(failed.deviceCopyStatus, 'PERMISSION_DENIED');
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect(attempts.single.method, 'publishRecording');
    expect(attempts.single.arguments['srcPath'], source.path);
    expect(attempts.single.arguments['displayName'], 'test');
    refuse = false;
    await Future.wait(
        [repo.retryDeviceCopy(failed), repo.retryDeviceCopy(failed)]);
    final saved = await when((r) => r.deviceCopySaved);
    expect(attempts.length, 2);
    expect(attempts.last.arguments['recordingKey'],
        attempts.first.arguments['recordingKey']);
    await repo.finishRecording(recording);
    await repo.retryDeviceCopy(saved);
    expect(attempts.length, 2);

    // Aucun fichier public pour un stop vide, tronqué ou explicitement annulé.
    for (final scenario in ['vide', 'tronque', 'annule']) {
      final file = await File('${temp.path}/$scenario.ts')
          .writeAsBytes(scenario == 'vide' ? [] : [1, 2, 3]);
      final other = await repo.startRecording(
          channelId: scenario, channelName: scenario, filePath: file.path);
      final complete = await repo.finishRecording(other,
          expectedBytes: scenario == 'tronque' ? 5 : null,
          publish: scenario != 'annule');
      expect(complete, scenario != 'tronque');
      expect(repo.current.firstWhere((r) => r.id == other.id).deviceCopyStatus,
          isNull);
    }
    expect(attempts.length, 2);
  });
}
