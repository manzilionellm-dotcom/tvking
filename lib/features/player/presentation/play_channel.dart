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
//  Routing cast (« connecte une fois, chaque tap suit ») :
//    Le picker global (bouton Cast dans la top-bar, cf. cast_button.dart)
//    permet de MÉMORISER une TV sans envoyer de flux tout de suite
//    (CastManager.selectDevice). L'app promet alors explicitement à
//    l'utilisateur (toast « Connecté à {TV}. Tape une chaîne pour
//    l'envoyer. », cf. castConnectedTapChannel) que le PROCHAIN tap de
//    chaîne partira vers cette TV — exactement ce que fait ce helper :
//    tant qu'une cible est mémorisée (CastManager.hasTarget), on caste
//    au lieu d'ouvrir le lecteur local. Documenté aussi par
//    CastManager.hasTarget lui-même (« Utilisé par playChannel() pour
//    décider de router le flux vers la TV »).
//    Un échec de cast (TV éteinte, réseau) retombe sur la lecture locale
//    — jamais d'écran bloqué à cause d'un cast qui rate.
//    Pour DÉCONNECTER : bouton Cast → device déjà connecté → déconnecter.
//
//  Toutes les surfaces (Home, Grid, Favoris, Search, Detail
//  sheet, TV Guide) passent par ce helper.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/crash/crash_reporting.dart';
import '../../../core/network/cellular_guard.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/data/cast_url_resolver.dart';
import '../../cast/domain/cast_device.dart';
import '../../cast/presentation/cast_button.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import 'video_player_screen.dart';

/// GARDE ANTI DOUBLE-OUVERTURE (portée process) : un double-tap (ou deux
/// taps rapprochés sur deux tuiles) traversait deux fois les `await`
/// ci-dessous et EMPILAIT deux VideoPlayerScreen → deux instances mpv,
/// deux connexions simultanées (fatal sur les comptes 1-connexion).
/// Posée AVANT le premier await, libérée en `finally` : tant qu'une
/// ouverture est en vol (lecteur poussé compris), les taps suivants
/// sont absorbés sans rien faire.
bool _opening = false;

Future<void> playChannel(
  BuildContext context,
  Channel channel, {
  List<Channel>? zapPlaylist,
  String? overrideUrl,
  String? overrideTitle,
}) async {
  if (_opening) return;
  _opening = true;
  try {
    await _playChannelInner(
      context,
      channel,
      zapPlaylist: zapPlaylist,
      overrideUrl: overrideUrl,
      overrideTitle: overrideTitle,
    );
  } finally {
    _opening = false;
  }
}

Future<void> _playChannelInner(
  BuildContext context,
  Channel channel, {
  List<Channel>? zapPlaylist,
  String? overrideUrl,
  String? overrideTitle,
}) async {
  RecentlyWatchedRepository.instance.record(channel.id);

  if (!context.mounted) return;
  // Garde données cellulaires (Wi-Fi only / avertissement data). Fail-open :
  // n'empêche jamais la lecture à cause d'un bug réseau.
  if (!await guardCellularPlayback(context)) return;
  if (!context.mounted) return;

  final CastManager mgr = CastManager.instance;
  final CastDevice? target = mgr.selectedDevice;
  if (target != null) {
    final String title = overrideTitle ?? channel.cleanName;
    try {
      // Même URL que le lecteur : format Xtream mémorisé appliqué
      // (terrain 2026-07-10 : panel « /live/ requis » → 404 sur l'URL
      // brute alors que le téléphone jouait très bien). Le CastManager
      // garde en plus une cascade de secours si le pré-vol échoue.
      final String castUrl =
          overrideUrl ?? await CastUrlResolver.resolve(channel);
      // VAGUE B — on partage la playlist de zap avec le CastManager :
      // la mini-barre globale (et l'overlay du lecteur) peuvent alors
      // proposer Ch+/Ch- qui changent la chaîne SUR LA TV, par le même
      // chemin quel que soit l'écran d'origine.
      if (zapPlaylist != null && zapPlaylist.length > 1) {
        mgr.setCastPlaylist(zapPlaylist, channel);
      }
      await mgr.castTo(
        target,
        streamUrl: castUrl,
        title: title,
        channelGenre: channel.category,
        imageUrl: channel.logoUrl,
      );
      if (context.mounted) {
        showCastRoutedToast(context,
            deviceName: target.displayName, channelName: title);
      }
      return; // Flux parti vers la TV : pas de lecteur local à ouvrir.
    } on Object catch (e, st) {
      // `on Object` : même un Error (TypeError…) du chemin cast ne doit
      // JAMAIS priver l'utilisateur du repli local — frontière de
      // session oblige (sinon : ni TV ni téléphone, écran mort).
      // Mais un Error est un BUG : on le remonte à la télémétrie crash
      // au lieu de le déguiser en simple « échec de cast » silencieux.
      if (e is! Exception) {
        CrashReporting.instance.recordError(e, st, context: 'playChannel.cast');
      }
      if (context.mounted) showCastFailedToast(context, e);
      // Repli : la lecture locale ci-dessous ne doit JAMAIS être bloquée
      // par un échec de cast (TV éteinte, hors portée, réseau…).
    }
  }

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
