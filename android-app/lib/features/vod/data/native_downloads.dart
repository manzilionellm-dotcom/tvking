// Petit adaptateur au moteur natif : même écran et mêmes identifiants.
// Les reprises historiques restent au moteur HTTP existant tant qu'un
// transfert natif correspondant n'a pas été créé.
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import '../../mobile_services/data/mobile_services.dart';

class NativeDownloads {
  static const String group = '7motion-vod-v1';
  static final FileDownloader engine = FileDownloader();
  static String taskId(String id) => '7motion-vod-$id';
  static Future<void> initialize(void Function(TaskUpdate) onUpdate) async {
    engine.updates
        .where((TaskUpdate e) => e.task.group == group)
        .listen(onUpdate);
    engine.configureNotificationForGroup(
      group,
      running: const TaskNotification(
        'Téléchargement',
        '{displayName} · {progress}',
      ),
      complete: const TaskNotification(
        'Téléchargement terminé',
        '{displayName}',
      ),
      error: const TaskNotification(
        'Téléchargement interrompu',
        'Reprends depuis 7MOTION',
      ),
      paused: const TaskNotification(
        'Téléchargement en pause',
        '{displayName}',
      ),
      progressBar: true,
    );
    await engine.start();
  }

  static Future<TaskRecord?> record(String id) =>
      engine.database.recordForId(taskId(id));
  static Future<bool> enqueue({
    required String id,
    required String url,
    required String filename,
    required String name,
  }) async {
    await MobileServices.instance.initialize();
    final DownloadTask task = DownloadTask(
      taskId: taskId(id),
      url: url,
      filename: filename,
      directory: 'Telechargements',
      baseDirectory: BaseDirectory.applicationDocuments,
      group: group,
      displayName: name,
      metaData: id,
      updates: Updates.statusAndProgress,
      allowPause: true,
      requiresWiFi: MobileServices.instance.wifiDownloads,
      retries: 3,
      headers: const <String, String>{'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'},
      transferHints: const <TransferHint>{
        TransferHint.userInitiated,
        TransferHint.largeFile,
      },
    );
    return engine.enqueue(task);
  }

  static Future<bool> pause(String id) async {
    final TaskRecord? r = await record(id);
    return r?.task is DownloadTask
        ? engine.pause(r!.task as DownloadTask)
        : false;
  }

  static Future<bool> resume(String id) async {
    final TaskRecord? r = await record(id);
    if (r?.task is! DownloadTask) return false;
    final DownloadTask task = r!.task as DownloadTask;
    if (r.status == TaskStatus.running ||
        r.status == TaskStatus.enqueued ||
        r.status == TaskStatus.waitingToRetry)
      return true;
    if (r.status == TaskStatus.paused) return engine.resume(task);
    return engine.enqueue(task);
  }

  static Future<void> delete(String id) async {
    await engine.cancelTaskWithId(taskId(id));
    await engine.database.deleteRecordWithId(taskId(id));
  }
}
