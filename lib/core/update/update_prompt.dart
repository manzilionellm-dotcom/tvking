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

import 'update_service.dart';

/// Verifie une MAJ et, le cas echeant, propose de l'installer.
/// Non bloquant : si rien de neuf ou erreur, ne fait rien.
Future<void> maybePromptUpdate(BuildContext context) async {
  final UpdateInfo? update = await UpdateService.instance.check();
  if (update == null) return;
  if (!context.mounted) return;

  final bool accept = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Mise à jour disponible'),
          content: Text(
            update.versionName.isNotEmpty
                ? 'La version ${update.versionName} est disponible. '
                    'Elle s\'installe par-dessus l\'app actuelle — '
                    'tes favoris et réglages sont conservés.'
                : 'Une nouvelle version est disponible. Elle s\'installe '
                    'par-dessus l\'app actuelle — tes favoris et réglages '
                    'sont conservés.',
          ),
          actions: <Widget>[
            if (!update.mandatory)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Plus tard'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Mettre à jour'),
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
        title: const Text('Téléchargement…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (BuildContext _, double p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 12),
              Text(p > 0 ? '${(p * 100).toStringAsFixed(0)} %' : 'Démarrage…'),
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
      const SnackBar(
        content: Text(
          'Échec du téléchargement. Réessaie, ou télécharge depuis le lien direct.',
        ),
      ),
    );
  }
  // Si ok : l'installateur Android est ouvert ; l'utilisateur confirme.
}
