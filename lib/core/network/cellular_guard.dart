// =========================================================
//  cellular_guard.dart — Garde "données cellulaires" avant lecture
// =========================================================
//  L'IPTV consomme beaucoup de data. Sur mobile, on veut éviter la
//  facture surprise : avant de lancer un flux, on vérifie le réseau.
//
//   - Wi-Fi / Ethernet           → on laisse passer (aucun dialogue).
//   - Cellulaire + `wifiOnly`    → on bloque, avec option "Lire quand
//                                   même" (ne contourne pas le réglage,
//                                   juste cette fois).
//   - Cellulaire + `warnOnCellular` → on avertit une fois, avec
//                                   "Ne plus avertir".
//
//  FAIL-OPEN : toute erreur (pas de plugin, état réseau inconnu) →
//  on autorise la lecture. La garde ne doit JAMAIS empêcher de
//  regarder à cause d'un bug.
//
//  Branché au CHOKEPOINT unique `playChannel()` → couvre Home, Grid,
//  Favoris, Search, Detail, TV Guide sans duplication.
// =========================================================

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/player/data/player_settings.dart';
import '../i18n/l10n_extension.dart';

/// Retourne `true` si la lecture peut démarrer sur le réseau courant.
/// Affiche un dialogue si nécessaire (cellulaire). Fail-open.
Future<bool> guardCellularPlayback(BuildContext context) async {
  try {
    final List<ConnectivityResult> conn =
        await Connectivity().checkConnectivity();

    final bool onWifiOrEthernet = conn.contains(ConnectivityResult.wifi) ||
        conn.contains(ConnectivityResult.ethernet);
    final bool onCellular = conn.contains(ConnectivityResult.mobile);

    // Pas cellulaire (ou aussi en Wi-Fi) → on laisse passer.
    if (!onCellular || onWifiOrEthernet) return true;

    final PlayerSettings s = PlayerSettings.instance;

    // Wi-Fi uniquement : bloque, mais propose "Lire quand même".
    if (s.wifiOnly) {
      if (!context.mounted) return false;
      final bool playAnyway = await showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: Text(ctx.l10n.cellularWifiOnlyTitle),
              content: Text(ctx.l10n.cellularWifiOnlyBody),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(ctx.l10n.buttonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(ctx.l10n.cellularPlayAnyway),
                ),
              ],
            ),
          ) ??
          false;
      return playAnyway;
    }

    // Avertissement simple (une fois, avec "Ne plus avertir").
    if (s.warnOnCellular) {
      if (!context.mounted) return false;
      bool dontWarnAgain = false;
      final bool proceed = await showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => StatefulBuilder(
              builder: (BuildContext ctx, void Function(void Function()) setLocal) =>
                  AlertDialog(
                title: Text(ctx.l10n.cellularWarnTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(ctx.l10n.cellularWarnBody),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dontWarnAgain,
                      onChanged: (bool? v) =>
                          setLocal(() => dontWarnAgain = v ?? false),
                      title: Text(ctx.l10n.cellularDontWarnAgain),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(ctx.l10n.buttonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(ctx.l10n.buttonContinue),
                  ),
                ],
              ),
            ),
          ) ??
          false;
      if (proceed && dontWarnAgain) {
        await s.setWarnOnCellular(false);
      }
      return proceed;
    }

    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('[CellularGuard] fail-open: $e');
    return true; // fail-open : jamais bloquer à cause d'un bug
  }
}
