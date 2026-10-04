// =========================================================
//  tv_panel_notice.dart — L'annonce du revendeur, sur l'accueil
// =========================================================
//  Une carte, pas une fenêtre : le focus reste sur les tuiles et on
//  MONTE jusqu'au bouton « Vu » pour la fermer. Sur une télé il n'y a
//  pas de notification système : c'est ici que l'annonce vit, jamais
//  sur l'image en plein écran.
//
//  Un lien ne s'ouvre pas à la télécommande : s'il y en a un, on montre
//  un QR que le téléphone photographie. Le libellé du bouton (« cta »)
//  vient du panel ; sinon « Sur ton téléphone ».
// =========================================================

import 'package:flutter/material.dart';

import '../../box_extras/box_text.dart';
import '../../simple_home/data/announcement_repository.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import 'panel_button.dart';

class TvPanelNotice extends StatelessWidget {
  const TvPanelNotice({
    super.key,
    required this.notice,
    required this.onSeen,
  });

  final Announcement notice;

  /// « Vu » : l'annonce ne revient plus (jusqu'à la prochaine).
  final VoidCallback onSeen;

  /// Icône et couleur selon la catégorie posée au panel
  /// (`nouveaute` | `promo` | `info` | `maintenance`).
  static ({IconData icon, Color color}) styleFor(String kind) {
    switch (kind) {
      case 'nouveaute':
        return (icon: Icons.auto_awesome_rounded, color: TvTokens.accentBright);
      case 'promo':
        return (icon: Icons.local_offer_rounded, color: TvTokens.accentBright);
      case 'maintenance':
        return (icon: Icons.build_rounded, color: TvTokens.live);
      default:
        return (icon: Icons.info_outline_rounded, color: TvTokens.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color color}) style = styleFor(notice.kind);
    final bool hasLink = notice.url.isNotEmpty;
    final String linkLabel = notice.cta.trim().isNotEmpty
        ? notice.cta.trim()
        : boxText(context, 'Sur ton téléphone', 'On your phone');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(style.icon, size: 28, color: style.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (notice.title.trim().isNotEmpty)
                      Text(
                        notice.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(
                          TvDimens.titleS,
                          weight: FontWeight.w800,
                          color: TvTokens.text,
                        ),
                      ),
                    if (notice.body.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        notice.body.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        PanelButton(
                          label: boxText(context, 'Vu', 'Got it'),
                          icon: Icons.check_rounded,
                          onSelect: onSeen,
                        ),
                        if (hasLink) ...<Widget>[
                          const SizedBox(width: 14),
                          const Icon(Icons.qr_code_scanner_rounded,
                              size: 18, color: TvTokens.mutedDim),
                          const SizedBox(width: 6),
                          Text(
                            linkLabel,
                            style: TvTokens.ui(TvDimens.caption,
                                color: TvTokens.mutedDim),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (hasLink) ...<Widget>[
                const SizedBox(width: 16),
                PanelQr(data: notice.url, size: 96),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
