// =========================================================
//  cast_mini_bar.dart — Mini-barre "Cast en cours"
// =========================================================
//  Bandeau flottant visible globalement quand une session de
//  cast est active. Permet de mettre en pause / reprendre /
//  déconnecter sans avoir à rouvrir le player.
//
//  À placer en haut du Stack racine de l'écran d'accueil
//  (juste au-dessus du contenu, en dessous de la status bar).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/cast_manager.dart';
import 'cast_picker_sheet.dart';
import '../../tv/core/tv_app_tokens.dart';

class CastMiniBar extends StatelessWidget {
  const CastMiniBar({super.key, this.manager});

  final CastManager? manager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager ?? CastManager.instance,
      builder: (BuildContext context, _) {
        final CastManager mgr = manager ?? CastManager.instance;
        final palette = Theme.of(context).extension<TvAppTokens>();
        final accent = palette?.accentBright ?? AppColors.accent;
        if (!mgr.hasActiveSession) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette?.panel ?? AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.15),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              InkResponse(
                onTap: () => showCastPickerGlobal(context, manager: mgr),
                child: Icon(
                  Icons.cast_connected_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mgr.state == CastState.connecting
                          ? context.l10n.castConnecting
                          : mgr.isCasting
                              ? context.l10n.castInProgressTitle
                              : context.l10n.castConnected,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: accent,
                        fontSize: 10,
                      ),
                    ),
                    if (!mgr.hasProtectedSession &&
                        mgr.currentTitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        mgr.currentTitle!,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (mgr.device != null)
                      Text(
                        '→ ${mgr.device!.name}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // VAGUE B — zap « télécommande pure » : Ch- / Ch+ changent
              // la chaîne SUR LA TV via la session en cours (le contexte
              // de zap est posé par le lecteur ou playChannel). Masqués
              // tant qu'aucune playlist n'est connue.
              if (mgr.canZapOnCast) ...<Widget>[
                IconButton(
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white,
                  ),
                  tooltip: context.l10n.castZapPrevTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => mgr.zapCastPrev(),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                  ),
                  tooltip: context.l10n.castZapNextTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => mgr.zapCastNext(),
                ),
              ],
              IconButton(
                icon: Icon(
                  mgr.state == CastState.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: Colors.white,
                ),
                tooltip: mgr.state == CastState.paused
                    ? context.l10n.buttonResume
                    : context.l10n.playerPause,
                onPressed: !mgr.isCasting
                    ? null
                    : () {
                        if (mgr.state == CastState.paused) {
                          mgr.resume();
                        } else {
                          mgr.pause();
                        }
                      },
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: AppColors.live,
                ),
                tooltip: context.l10n.castStopTooltip,
                onPressed: () => mgr.disconnect(),
              ),
            ],
          ),
        );
      },
    );
  }
}
