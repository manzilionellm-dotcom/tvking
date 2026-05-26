// =========================================================
//  play_channel.dart — Helper pour ouvrir une chaîne
// =========================================================
//  Centralise l'action "lancer une chaîne". Avantages :
//    - Un seul endroit pour ajouter une transition spécifique
//    - On enregistre automatiquement dans l'historique récent
//    - Optionnellement, on passe une liste de chaînes pour
//      activer le zapping ⏮ / ⏭ dans le player
//    - Optionnellement, on passe une `overrideUrl` (catch-up)
//      qui sera lue au lieu de l'URL live de la chaîne
//
//  IMPORTANT — Routing cast :
//    Si une TV est déjà connectée via le bouton Cast global
//    (CastManager.hasTarget), on envoie le flux directement à
//    la TV au lieu d'ouvrir le player local. C'est exactement
//    le modèle YouTube/Netflix : "connecte-toi une fois, puis
//    tout tap part vers la TV".
//
//  Toutes les surfaces (Home, Grid, Favoris, Search, Detail
//  sheet, TV Guide) passent par ce helper.
// =========================================================

import 'package:flutter/material.dart';

import '../../cast/data/cast_manager.dart';
import '../../cast/domain/cast_device.dart';
import '../../cast/presentation/cast_button.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import 'video_player_screen.dart';

Future<void> playChannel(
  BuildContext context,
  Channel channel, {
  List<Channel>? zapPlaylist,
  String? overrideUrl,
  String? overrideTitle,
}) async {
  RecentlyWatchedRepository.instance.record(channel.id);

  // ----- Cast actif ? → on envoie à la TV au lieu du player local -----
  final CastManager mgr = CastManager.instance;
  final CastDevice? target = mgr.selectedDevice ?? mgr.device;
  if (target != null) {
    final String url = overrideUrl ?? channel.streamUrl;
    final String title = overrideTitle ?? channel.cleanName;
    try {
      await mgr.castTo(target, streamUrl: url, title: title);
      if (context.mounted) {
        showCastRoutedToast(
          context,
          deviceName: target.name,
          channelName: title,
        );
      }
      return;
    } on Exception catch (e) {
      // Échec du cast → on retombe sur le player local
      if (context.mounted) showCastFailedToast(context, e);
    }
  }

  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(
        channel: channel,
        zapPlaylist: zapPlaylist,
        overrideUrl: overrideUrl,
        overrideTitle: overrideTitle,
      ),
    ),
  );
}
