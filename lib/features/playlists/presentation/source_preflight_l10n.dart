// =========================================================
//  source_preflight_l10n.dart — Traduction UI des erreurs de source
// =========================================================
//  La couche data (SourcePreflight) CLASSE les erreurs en raisons typées
//  (SourcePreflightIssue) sans connaître Flutter ; ici, côté UI, chaque
//  raison devient une phrase dans la langue de l'utilisateur. Avant ce
//  fichier, humanize() renvoyait du français en dur — affiché tel quel
//  dans les 7 autres langues (chantier traductions du 20/08).
// =========================================================
import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../data/source_preflight.dart';

/// Phrase TRADUITE (langue de l'utilisateur) pour n'importe quelle erreur
/// survenue pendant le test ou l'ajout d'une source. À utiliser partout où
/// l'on affichait `SourcePreflight.humanize(e)` (qui reste la projection
/// française, pour les journaux).
String sourcePreflightErrorText(BuildContext context, Object error) {
  return switch (SourcePreflight.classify(error)) {
    SourcePreflightIssue.badLink => context.l10n.srcErrBadLink,
    SourcePreflightIssue.schemeNotAllowed => context.l10n.srcErrScheme,
    SourcePreflightIssue.authRefused => context.l10n.srcErrAuthRefused,
    SourcePreflightIssue.wrongPath => context.l10n.srcErrWrongPath,
    SourcePreflightIssue.notAPlaylist => context.l10n.srcErrNotAPlaylist,
    SourcePreflightIssue.listTooLarge => context.l10n.srcErrTooLarge,
    SourcePreflightIssue.xtreamBadCredentials =>
      context.l10n.srcErrXtreamCredentials,
    SourcePreflightIssue.xtreamAccountInactive =>
      context.l10n.srcErrXtreamInactive,
    SourcePreflightIssue.xtreamNotAPanel => context.l10n.srcErrXtreamNotAPanel,
    SourcePreflightIssue.xtreamUnexpected =>
      context.l10n.srcErrXtreamUnexpected,
    SourcePreflightIssue.timeout => context.l10n.srcErrTimeout,
    SourcePreflightIssue.tlsFailed => context.l10n.srcErrTls,
    SourcePreflightIssue.hostNotFound => context.l10n.srcErrHostNotFound,
    SourcePreflightIssue.portRefused => context.l10n.srcErrPortRefused,
    SourcePreflightIssue.connectionFailed => context.l10n.srcErrConnection,
    SourcePreflightIssue.connectionInterrupted =>
      context.l10n.srcErrInterrupted,
    SourcePreflightIssue.noChannelsFound => context.l10n.srcErrNoChannels,
    SourcePreflightIssue.generic => context.l10n.srcErrGeneric,
  };
}
