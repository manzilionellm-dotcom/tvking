// =========================================================
//  update_prompt.dart — UI de la mise a jour in-app
// =========================================================
//  Affiche une boite "Mise a jour disponible" non bloquante (sauf si
//  `mandatory`), puis une barre de progression pendant le
//  telechargement, et lance l'installateur Android.
//
//  Appele depuis main.dart apres le 1er frame (non bloquant, fail-open).
// =========================================================

import 'package:flutter/material.dart';

import '../i18n/l10n_extension.dart';
import '../theme/app_colors.dart';
import 'update_service.dart';

/// AUTO-MAJ « sans y penser » : appelée au démarrage, à chaque retour au
/// premier plan et périodiquement (12 h). Dès qu'une nouvelle version est
/// publiée, on la télécharge EN SILENCE (petit bandeau discret, non bloquant),
/// puis on ouvre DIRECTEMENT l'installateur Android. Il ne reste AUCUNE
/// question « Mettre à jour ? » : l'unique geste restant est le bouton
/// « Installer » d'Android — OBLIGATOIRE et non contournable pour un APK hors
/// Play Store (aucune app ne peut s'installer 100 % seule sans être
/// app-système). Fail-open : rien de neuf, réseau KO ou build Play → ne fait
/// rien. Le téléchargement n'a lieu qu'UNE fois par version (ensuite le
/// buildNumber correspond, plus aucune détection).
Future<void> maybePromptUpdate(BuildContext context) async {
  final UpdateInfo? update = await UpdateService.instance.check();
  if (update == null || !context.mounted) return;

  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  // Bandeau discret : le client VOIT qu'une mise à jour arrive, sans avoir à
  // décider quoi que ce soit — le téléchargement se fait tout seul en fond.
  messenger?.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 45),
      content: Text(context.l10n.moviesDownloading),
    ),
  );

  final bool ok = await UpdateService.instance.downloadAndInstall(update);
  if (!context.mounted) return;
  messenger?.clearSnackBars();

  if (!ok) {
    // Repli silencieux : au prochain passage on réessaiera tout seul.
    messenger?.showSnackBar(
      SnackBar(content: Text(context.l10n.updateDownloadFailed)),
    );
  }
  // Si ok : l'installateur Android est ouvert ; l'unique tap « Installer »
  // met à jour PAR-DESSUS (même clé maîtresse + même package → favoris et
  // réglages conservés, aucune désinstallation).
}

/// Vérification MANUELLE (bouton « Vérifier les mises à jour » des
/// Réglages). Contrairement à l'auto-MAJ, elle DONNE UN RETOUR dans tous
/// les cas :
///   • MAJ dispo   → la même boîte « Mettre à jour » (téléchargement +
///                   installation directe) ;
///   • déjà à jour → « Tu as déjà la dernière version » ;
///   • réseau KO   → « Impossible de vérifier, réessaie ».
Future<void> checkForUpdatesInteractive(BuildContext context) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 15),
      content: Text(context.l10n.updateSearching),
    ),
  );
  final UpdateCheckResult res = await UpdateService.instance.checkDetailed();
  if (!context.mounted) return;
  messenger.clearSnackBars();
  switch (res.status) {
    case UpdateAvailability.available:
      final UpdateInfo? info = res.info;
      if (info != null) await _promptAndInstall(context, info);
      break;
    case UpdateAvailability.upToDate:
      final String? v = res.versionName;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            (v != null && v.isNotEmpty)
                ? context.l10n.updateUpToDateVersion(v)
                : context.l10n.updateUpToDate,
          ),
        ),
      );
      break;
    case UpdateAvailability.unavailable:
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(context.l10n.updateCheckFailed),
        ),
      );
      break;
  }
}

/// Boîte « Mise à jour disponible → Mettre à jour » puis, si accepté,
/// téléchargement + installation. Partagée par l'auto-MAJ et le bouton
/// manuel.
Future<void> _promptAndInstall(BuildContext context, UpdateInfo update) async {
  final bool accept = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(ctx.l10n.updateAvailableTitle),
          content: Text(
            update.versionName.isNotEmpty
                ? ctx.l10n.updateBodyVersion(update.versionName)
                : ctx.l10n.updateBodyGeneric,
          ),
          actions: <Widget>[
            if (!update.mandatory)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ctx.l10n.resumeBannerDismiss),
              ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.updateNow),
            ),
          ],
        ),
      ) ??
      false;

  if (!accept || !context.mounted) return;
  await _downloadWithProgress(context, update);
}

Future<void> _downloadWithProgress(
  BuildContext context,
  UpdateInfo update,
) async {
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  bool dialogOpen = true;

  // Boite de progression non annulable.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        // « Téléchargement… » : même libellé que le statut VOD → on
        // réutilise la clé existante moviesDownloading.
        title: Text(ctx.l10n.moviesDownloading),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (BuildContext _, double p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 12),
              // Le pourcentage garde son format numérique via la clé
              // paramétrée tvPercent ("{percent} %").
              Text(p > 0
                  ? ctx.l10n.tvPercent((p * 100).round())
                  : ctx.l10n.updateStarting),
            ],
          ),
        ),
      ),
    ),
  );

  final bool ok = await UpdateService.instance.downloadAndInstall(
    update,
    onProgress: (double p) => progress.value = p,
  );

  // Ferme la boite de progression.
  if (dialogOpen && context.mounted) {
    dialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }
  progress.dispose();

  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.updateDownloadFailed),
      ),
    );
  }
  // Si ok : l'installateur Android est ouvert ; l'utilisateur confirme.
}
