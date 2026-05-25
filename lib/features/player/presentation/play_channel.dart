// =========================================================
//  play_channel.dart — Helper pour ouvrir une chaîne
// =========================================================
//  Petit helper utilisé partout dans l'app (Home, Grid,
//  Favoris, Recherche, Catégorie...) pour pousser le
//  VideoPlayerScreen avec la bonne chaîne.
//
//  Centraliser ça permet : si demain on veut ajouter une
//  transition spécifique, ou une page intermédiaire avec
//  les infos EPG, on le fait à un seul endroit.
// =========================================================

import 'package:flutter/material.dart';

import '../../channels/domain/channel.dart';
import 'video_player_screen.dart';

Future<void> playChannel(BuildContext context, Channel channel) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(channel: channel),
      // fullscreenDialog: false (transition standard left-to-right)
    ),
  );
}
