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

class CastMiniBar extends StatelessWidget {
  const CastMiniBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CastManager.instance,
      builder: (BuildContext context, _) {
        final CastManager mgr = CastManager.instance;
        if (!mgr.isCasting && mgr.state != CastState.connecting) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.15),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.cast_connected_rounded,
                color: AppColors.accent,
                size: 20,
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
                          : context.l10n.castInProgressTitle,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.accent,
                        fontSize: 10,
                      ),
                    ),
                    if (mgr.currentTitle != null) ...<Widget>[
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
                onPressed: () {
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
