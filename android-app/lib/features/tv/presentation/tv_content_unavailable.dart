// Une route reçue directement doit respecter les mêmes exclusions que les
// catalogues. Cet état ne crée aucun lecteur, ne charge aucune affiche et
// n'ouvre aucune connexion au fournisseur.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';

class NovatubeUnavailableState<T extends StatefulWidget> extends State<T> {
  @override
  Widget build(BuildContext context) => TvShell(
        child: Center(
          key: const ValueKey<String>('novatube-content-unavailable'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(context.l10n.detailCatchupUnavailable,
                  style: TvTokens.ui(TvDimens.title)),
              const SizedBox(height: TvDimens.touchSafeV),
              if (Navigator.of(context).canPop()) const BackButton(),
            ],
          ),
        ),
      );
}
