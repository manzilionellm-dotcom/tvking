// =========================================================
//  tv_player_launcher.dart — Ouverture du lecteur SOUS VERROU
// =========================================================
//  Garde anti-double-lecteur PARTAGÉE : un double appui OK (télécommandes
//  qui « rebondissent », impatience) poussait DEUX TvPlayerScreen → 2
//  ExoPlayer + 2 connexions amont — mortel sur les comptes 1-connexion.
//  Seuls tv_live_screen et tv_movie_detail_screen avaient leur verrou
//  local (_openingPlayer) ; tous les autres points d'ouverture passent
//  désormais par CE helper, protégé par un verrou DE PROCESSUS (un seul
//  lecteur peut s'ouvrir à la fois, quel que soit l'écran appelant).
// =========================================================
import 'package:flutter/material.dart';

import '../../channels/domain/channel.dart';
import '../core/tv_cine_route.dart';
import 'tv_player_screen.dart';

/// Verrou de processus : vrai tant qu'un lecteur ouvert via [openTvPlayer]
/// est en train de s'ouvrir OU est à l'écran. Toujours relâché en `finally`
/// (le bug du verrou jamais relâché ne doit pas revivre ici).
bool _openingTvPlayer = false;

/// Pousse le lecteur plein écran pour [channels] à partir de [startIndex],
/// sous verrou global. Renvoie `true` quand le lecteur a été ouvert PUIS
/// fermé (l'appelant peut faire son travail « au retour » : restaurer un
/// focus, relancer un aperçu…) ; `false` si l'ouverture a été IGNORÉE
/// (double appui, paramètres invalides) — dans ce cas l'appelant ne doit
/// RIEN faire (un autre lecteur est peut-être encore à l'écran).
///
/// [cineRoute] : transition « cinéma » (VOD) au lieu du MaterialPageRoute.
/// [settleFirst] : attend la fin de la frame en cours AVANT le push — pour
/// les écrans qui viennent de libérer un aperçu vidéo (le lecteur natif de
/// l'aperçu doit être démonté avant d'ouvrir le plein écran).
Future<bool> openTvPlayer(
  BuildContext context, {
  required List<Channel> channels,
  required int startIndex,
  bool cineRoute = false,
  bool settleFirst = false,
}) async {
  if (_openingTvPlayer) return false; // double-activation ignorée
  if (channels.isEmpty || startIndex < 0 || startIndex >= channels.length) {
    return false;
  }
  _openingTvPlayer = true;
  try {
    if (settleFirst) {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return false;
    }
    Widget builder(BuildContext _) =>
        TvPlayerScreen(channels: channels, startIndex: startIndex);
    await Navigator.of(context).push(
      cineRoute
          ? TvCineRoute<void>(builder: builder)
          : MaterialPageRoute<void>(builder: builder),
    );
    return true;
  } finally {
    _openingTvPlayer = false;
  }
}
