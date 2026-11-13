// Les identifiants du parseur ne changent pas : seuls les textes affichés
// sont traduits. Un changement de langue actualise aussi une erreur ouverte.
import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/domain/open_source_input.dart';

String sourceErrorText(BuildContext context, String error) => switch (error) {
  OpenSourceInput.errNeedUrl => context.l10n.tvSourceNeedUrl,
  OpenSourceInput.errNeedXtream => context.l10n.tvSourceNeedXtream,
  OpenSourceInput.errNeedPlayerCreds => context.l10n.tvSourceNeedCredentials,
  OpenSourceInput.errBadScheme => context.l10n.tvSourceBadScheme,
  'm3u_failed' => context.l10n.tvAddM3uFailed,
  'local_unavailable' => context.l10n.tvLocalFileUnavailable,
  'local_empty' => context.l10n.tvLocalFileEmpty,
  'local_too_big' => context.l10n.tvLocalFileTooBig,
  _ => context.l10n.tvConnectError,
};
