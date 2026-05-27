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
//  IMPORTANT — Routing cast (NON-INTRUSIF) :
//    Tap chaîne = TOUJOURS ouverture du player local sur le
//    téléphone. Le cast n'est PAS auto-routé, même si une TV
//    est déjà sélectionnée dans CastManager. Choix volontaire :
//    le user nous a demandé que le cast soit un "accessoire
//    qu'on déclenche quand on le veut, pas qui vient tout seul".
//
//    Pour caster : pendant la lecture, tap explicite sur le
//    bouton Cast dans la top-bar du player → ouverture du
//    picker → sélection device → envoi du flux.
//
//    Avantages :
//      - Pas de surprise : la chaîne s'ouvre toujours sur le tel
//      - On peut prévisualiser avant de caster
//      - Le device cast reste sélectionné en arrière-plan, prêt
//        pour le prochain envoi explicite (pas besoin de re-scan)
//
//  Toutes les surfaces (Home, Grid, Favoris, Search, Detail
//  sheet, TV Guide) passent par ce helper.
// =========================================================

import 'package:flutter/material.dart';

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

  // Pas de forçage de rotation ici : l'utilisateur veut que la vidéo
  // SUIVE le positionnement physique du téléphone (style YouTube /
  // Netflix). C'est `VideoPlayerScreen.initState` qui élargit les
  // orientations autorisées pour que ça tourne tout seul au moindre
  // mouvement du capteur — y compris quand l'auto-rotate système
  // Android est désactivé.

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
