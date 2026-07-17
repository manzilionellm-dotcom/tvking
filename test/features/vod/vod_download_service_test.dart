// =========================================================
//  vod_download_service_test.dart — Téléchargements intelligents (unités)
// =========================================================
//  On teste les briques PURES du service (aucun réseau, aucun disque) :
//    • le choix du prochain job de la file sérielle (pickNext) ;
//    • le parsing de `df -k` (garde d'espace disque) ;
//    • la (dé)sérialisation JSON — y compris les nouveaux champs épisode
//      et les remappages de statut au redémarrage (downloading→paused,
//      noSpace→queued) qui garantissent qu'un téléchargement interrompu
//      REPREND au lieu de rester figé.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/data/vod_download_service.dart';

VodDownload _d(String id, VodDownloadStatus s, {bool episode = false}) =>
    VodDownload(
      id: id,
      name: 'n$id',
      filePath: '/tmp/$id.mp4',
      streamUrl: 'http://example.test/$id.mp4',
      isEpisode: episode,
      status: s,
    );

void main() {
  group('pickNext (file sérielle)', () {
    test('prend le premier queued, dans l\'ordre d\'insertion', () {
      final List<VodDownload> items = <VodDownload>[
        _d('a', VodDownloadStatus.done),
        _d('b', VodDownloadStatus.queued),
        _d('c', VodDownloadStatus.queued),
      ];
      expect(VodDownloadService.pickNext(items)?.id, 'b');
    });

    test('ignore paused / error / noSpace / done', () {
      final List<VodDownload> items = <VodDownload>[
        _d('a', VodDownloadStatus.paused),
        _d('b', VodDownloadStatus.error),
        _d('c', VodDownloadStatus.noSpace),
        _d('d', VodDownloadStatus.done),
      ];
      expect(VodDownloadService.pickNext(items), isNull);
    });

    test('liste vide → null', () {
      expect(VodDownloadService.pickNext(const <VodDownload>[]), isNull);
    });
  });

  group('parseDfAvailableBytes (garde d\'espace)', () {
    test('sortie toybox/GNU classique', () {
      const String out = 'Filesystem     1K-blocks    Used Available Use% '
          'Mounted on\n/dev/block/dm-5  57541632 3126016  54415616   6% '
          '/storage/emulated';
      expect(VodDownloadService.parseDfAvailableBytes(out),
          54415616 * 1024);
    });

    test('nom de volume avec espace : la colonne % fait foi', () {
      const String out =
          'Filesystem 1K-blocks Used Available Use% Mounted on\n'
          'My Disk 1000 500 400 50% /mnt/disk';
      expect(VodDownloadService.parseDfAvailableBytes(out), 400 * 1024);
    });

    test('en-tête seul ou sortie vide → null (on ne bloque pas)', () {
      expect(
          VodDownloadService.parseDfAvailableBytes(
              'Filesystem 1K-blocks Used Available Use% Mounted on'),
          isNull);
      expect(VodDownloadService.parseDfAvailableBytes(''), isNull);
    });

    test('sortie inattendue → null, jamais d\'exception', () {
      expect(VodDownloadService.parseDfAvailableBytes('n/a\nrien à voir'),
          isNull);
    });
  });

  group('VodDownload JSON', () {
    test('aller-retour complet, épisode inclus', () {
      final VodDownload d = VodDownload(
        id: 'ep-42',
        name: 'S01E03 · Pilote',
        filePath: '/data/dl/ep-42.mkv',
        streamUrl: 'http://example.test/series/u/p/42.mkv',
        posterUrl: 'http://example.test/p.jpg',
        isEpisode: true,
        groupName: 'Ma Série',
        totalBytes: 1000,
        downloadedBytes: 1000,
        status: VodDownloadStatus.done,
      );
      final VodDownload back = VodDownload.fromJson(
          Map<String, dynamic>.from(d.toJson()));
      expect(back.id, 'ep-42');
      expect(back.isEpisode, isTrue);
      expect(back.groupName, 'Ma Série');
      expect(back.status, VodDownloadStatus.done);
      expect(back.progress, 1.0);
    });

    test('redémarrage : downloading → paused (reprise manuelle possible)',
        () {
      final VodDownload d = _d('x', VodDownloadStatus.downloading);
      expect(VodDownload.fromJson(Map<String, dynamic>.from(d.toJson())).status,
          VodDownloadStatus.paused);
    });

    test('redémarrage : noSpace → queued (la place a pu revenir)', () {
      final VodDownload d = _d('x', VodDownloadStatus.noSpace);
      expect(VodDownload.fromJson(Map<String, dynamic>.from(d.toJson())).status,
          VodDownloadStatus.queued);
    });

    test('JSON ancien (sans champs épisode) → film par défaut', () {
      final VodDownload back = VodDownload.fromJson(<String, dynamic>{
        'id': 'v1',
        'name': 'Film',
        'filePath': '/f.mp4',
        'streamUrl': 'http://example.test/f.mp4',
        'status': 'done',
      });
      expect(back.isEpisode, isFalse);
      expect(back.groupName, isEmpty);
      expect(back.isComplete, isTrue);
    });
  });
}
