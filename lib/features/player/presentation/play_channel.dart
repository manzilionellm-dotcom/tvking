// =========================================================
//  play_channel.dart — Helper pour ouvrir une chaîne
// =========================================================
//  Centralise l'action "lancer une chaîne". Avantages :
//    - Un seul endroit pour ajouter une transition spécifique
//    - On enregistre automatiquement dans l'historique récent
//    - Optionnellement, on passe une liste de chaînes pour
//      activer le zapping ⏮ / ⏭ dans le player
//
//  Toutes les surfaces (Home, Grid, Favoris, Search, Detail
//  sheet) passent par ce helper.
// =========================================================

import 'package:flutter/material.dart';

import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import 'video_player_screen.dart';

Future<void> playChannel(
  BuildContext context,
  Channel channel, {
  List<Channel>? zapPlaylist,
}) {
  RecentlyWatchedRepository.instance.record(channel.id);

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(
        channel: channel,
        zapPlaylist: zapPlaylist,
      ),
    ),
  );
}
