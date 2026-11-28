// Le code temporaire d'assistance est révélé seulement après un appui
// volontaire. Seul Atlas le crée et le retire ; ce dialogue ne fait aucune
// requête et n'enregistre aucun identifiant dans les préférences.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../subscription/data/novatube_atlas.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';

Future<void> showNovatubeSupportDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        final tokens = TvAppTokens.of(context);
        return AlertDialog(
          backgroundColor: tokens.panel,
          title: Text(l10n.novatubeSupportTitle,
              style: tokens.ui(TvDimens.title, color: tokens.text)),
          content: ValueListenableBuilder<String?>(
            valueListenable: NovatubeAtlas.instance.recoveryCode,
            builder: (context, value, _) {
              final code = value?.trim() ?? '';
              // Isole le code de gauche à droite dans un paragraphe arabe.
              final message = code.isEmpty
                  ? l10n.novatubeSupportEmpty
                  : l10n.novatubeRecoveryCode('\u2066$code\u2069');
              return Semantics(
                liveRegion: true,
                child: Text(message,
                    style: tokens.body(TvDimens.body, color: tokens.text)),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.tvClose),
            ),
          ],
        );
      },
    );
