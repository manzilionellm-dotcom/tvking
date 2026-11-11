// État vide du lecteur NOVATUBE : seule une source saisie volontairement
// dans l'application peut alimenter les chaînes. Aucune attente d'activation,
// adresse MAC, publicité ou offre d'essai n'est présentée ici.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_shell.dart';
import 'tv_touch_components.dart';

class TvManualSourcePrompt extends StatelessWidget {
  const TvManualSourcePrompt({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('novatube-manual-source-prompt'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TvTouchPageHeader(title: context.l10n.tvNavLive),
          const SizedBox(height: TvDimens.touchSafeV),
          Text(context.l10n.tvNoChannels,
              style: TvTokens.display(TvDimens.headline)),
          const SizedBox(height: TvDimens.touchGap),
          Text(context.l10n.tvNoChannelsSold,
              style: TvTokens.ui(TvDimens.label, color: TvTokens.muted)),
          const SizedBox(height: TvDimens.touchSafeV),
          TvCtaButton(
            key: const ValueKey<String>('novatube-add-manual-source'),
            label: context.l10n.tvMySources,
            onSelect: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvAddSourceScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
