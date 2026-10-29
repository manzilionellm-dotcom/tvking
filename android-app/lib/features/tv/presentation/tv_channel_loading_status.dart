// =========================================================
//  État visible du premier chargement des chaînes.
// =========================================================
//  Les chiffres viennent exclusivement de l'import réel. La connexion ne
//  connaît ni le nombre de chaînes ni la durée : elle n'invente donc aucun
//  pourcentage. Seul l'enregistrement connaît son total et peut être mesuré.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_tokens.dart';
import 'tv_import_progress_label.dart';

class TvChannelLoadingStatus extends StatelessWidget {
  const TvChannelLoadingStatus({
    required this.checking,
    required this.importing,
    this.progress,
    this.result,
    super.key,
  });

  final bool checking;
  final bool importing;
  final ImportProgress? progress;
  final RemoteSyncResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bool active = checking || importing;
    // Un ancien compteur ne doit jamais survivre à un échec, à une absence
    // de liste ou à une nouvelle vérification sans import.
    final ImportProgress? current = importing ? progress : null;
    final String title;
    final String help;
    final IconData icon;
    if (importing) {
      title = l10n.tvChannelLoadingTitle;
      help = l10n.tvChannelLoadingHelp;
      icon = Icons.downloading_rounded;
    } else if (checking) {
      title = l10n.tvChannelCheckingTitle;
      help = l10n.tvChannelCheckingHelp;
      icon = Icons.wifi_find_rounded;
    } else if (result == RemoteSyncResult.networkError) {
      title = l10n.tvNetworkUnavailable;
      help = l10n.tvChannelNetworkHelp;
      icon = Icons.wifi_off_rounded;
    } else if (result == RemoteSyncResult.sourceFailed) {
      title = l10n.tvChannelSourceFailedTitle;
      help = l10n.tvChannelSourceFailedHelp;
      icon = Icons.playlist_remove_rounded;
    } else if (result == RemoteSyncResult.loaded) {
      title = l10n.tvChannelEmptyTitle;
      help = l10n.tvChannelEmptyHelp;
      icon = Icons.live_tv_rounded;
    } else {
      title = l10n.tvChannelWaitingTitle;
      help = l10n.tvChannelWaitingHelp;
      icon = Icons.playlist_add_rounded;
    }

    final ImportStage stage = current?.stage ?? ImportStage.connecting;
    final int phase = switch (stage) {
      ImportStage.connecting => 0,
      ImportStage.saving || ImportStage.done => 2,
      _ => 1,
    };
    final bool finished = importing && stage == ImportStage.done;
    // La fraction décrit UNIQUEMENT les écritures locales. Aucun temps
    // écoulé ni nombre de tentatives réseau n'est converti en progression.
    final double? fraction = current != null &&
            current.stage == ImportStage.saving &&
            current.total > 0
        ? (current.index / current.total).clamp(0.0, 1.0).toDouble()
        : null;
    final String? detail = importing
        ? importProgressLabel(
            context, current ?? const ImportProgress(ImportStage.connecting))
        : null;
    final int found = current?.stage == ImportStage.saving
        ? current!.total
        : current?.count ?? 0;

    return Container(
      key: const ValueKey<String>('tv-channel-loading-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(
          color: active ? TvTokens.accentDeep : TvTokens.lineSoft,
        ),
      ),
      // Pas de hauteur fixe : le texte agrandi et les traductions longues
      // peuvent prendre plusieurs lignes sans rogner le message.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: TvTokens.accentBright, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TvTokens.display(25, color: TvTokens.text)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(help, style: TvTokens.ui(13, color: TvTokens.muted)),
          if (active) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: <Widget>[
                _LoadingStep(
                  label: l10n.tvChannelStepConnection,
                  selected: phase == 0,
                  completed: phase > 0 || finished,
                ),
                _LoadingStep(
                  label: l10n.tvChannelStepReading,
                  selected: phase == 1,
                  completed: phase > 1 || finished,
                ),
                _LoadingStep(
                  label: l10n.tvChannelStepSaving,
                  selected: phase == 2,
                  completed: finished,
                ),
              ],
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 10),
              // found/category/done portent déjà leur compteur dans le
              // libellé traduit. Pendant saving, le total est le nombre
              // réellement analysé, et index le nombre déjà enregistré.
              if (found > 0 && stage == ImportStage.saving)
                Text(l10n.tvImpFound(ImportProgressBus.n(found)),
                    style: TvTokens.ui(15,
                        weight: FontWeight.w600,
                        color: TvTokens.accentBright)),
              Text(detail,
                  key: const ValueKey<String>('tv-channel-import-detail'),
                  style: TvTokens.ui(13, color: TvTokens.text)),
            ],
            if (!finished) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(TvTokens.rSmall),
                child: LinearProgressIndicator(
                  key: const ValueKey<String>('tv-channel-import-progress'),
                  value: fraction,
                  minHeight: 4,
                  color: TvTokens.accentBright,
                  backgroundColor: TvTokens.line,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep({
    required this.label,
    required this.selected,
    required this.completed,
  });

  final String label;
  final bool selected;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final Color color = selected || completed
        ? TvTokens.accentBright
        : TvTokens.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          completed
              ? Icons.check_circle_rounded
              : selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: TvTokens.ui(11, color: color))),
      ],
    );
  }
}
