import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/flavor/flavor.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/data/epg_targets.dart';
import '../../playlists/data/playlist_database.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';

/// Le guide seulement : aucune route panel, aucun changement de source,
/// d'abonnement ou de chaîne. Le système choisit l'heure d'exécution.
@pragma('vm:entry-point')
void mobileGuideDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != BackgroundGuide.taskName) return true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.reload();
      if (p.getBool('mobile.background_guide') != true ||
          await BackgroundGuide.foreground())
        return true;
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      final List<Playlist> playlists = await PlaylistRepository.instance
          .getAllPlaylists();
      for (final Playlist playlist
          in playlists
              .where((Playlist p) => !p.hidden && p.epgUrl?.isNotEmpty == true)
              .take(2)) {
        if (await BackgroundGuide.foreground()) break;
        if (playlist.type == PlaylistType.xtream) {
          final XtreamClient client = XtreamClient(
            serverUrl: playlist.xtreamServer!,
            username: playlist.xtreamUsername!,
            password: playlist.xtreamPassword!,
          );
          try {
            await client.fetchLiveChannels(
              playlistId: playlist.id!,
              categories: const <String, String>{},
            );
            final Map<String, List<String>> map = buildEpgIdMap(
              client.epgChannelIds,
            );
            if (map.isNotEmpty)
              await EpgRepository.instance.downloadAndImport(
                url: playlist.epgUrl!,
                channelIdMap: map,
                connectTimeout: const Duration(seconds: 12),
                idleTimeout: const Duration(seconds: 20),
              );
          } finally {
            client.dispose();
          }
        } else {
          final rows = await (await PlaylistDatabase.instance.database).query(
            'channels',
            columns: <String>['external_id'],
            where: 'playlist_id = ?',
            whereArgs: <Object?>[playlist.id],
          );
          final Set<String> ids = rows
              .map((Map<String, Object?> r) => r['external_id'] as String)
              .toSet();
          if (ids.isNotEmpty)
            await EpgRepository.instance.downloadAndImport(
              url: playlist.epgUrl!,
              knownChannelIds: ids,
              connectTimeout: const Duration(seconds: 12),
              idleTimeout: const Duration(seconds: 20),
            );
        }
      }
      await p.setInt(
        'mobile.background_guide_last',
        DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundGuide {
  static const String taskName = '7motion.guide.refresh';
  static bool _ready = false;
  static Future<File> _lease() async => File(
    '${(await getApplicationSupportDirectory()).path}/mobile-foreground.lease',
  );
  static Future<void> markForeground(bool value) async {
    try {
      await (await _lease()).writeAsString(
        value ? '${DateTime.now().millisecondsSinceEpoch}' : '0',
        flush: true,
      );
    } catch (_) {}
  }

  static Future<bool> foreground() async {
    final File f = await _lease();
    if (!await f.exists()) return false;
    final int at = int.tryParse(await f.readAsString()) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at < 90000;
  }

  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(
        'mobile.background_guide',
      ) ??
      false;
  static Future<void> configure(bool value) async {
    if (!Platform.isAndroid)
      throw StateError('Actualisation en arrière-plan disponible sur Android.');
    if (!_ready) {
      await Workmanager().initialize(mobileGuideDispatcher);
      _ready = true;
    }
    if (value) {
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: const Duration(hours: 6),
        initialDelay: const Duration(minutes: 20),
        constraints: Constraints(
          networkType: NetworkType.unmetered,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(taskName);
    }
    await (await SharedPreferences.getInstance()).setBool(
      'mobile.background_guide',
      value,
    );
  }
}
