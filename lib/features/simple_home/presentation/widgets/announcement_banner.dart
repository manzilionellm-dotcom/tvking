// =========================================================
//  announcement_banner.dart — Bandeau « annonce à tous »
// =========================================================
//  Affiche en haut de l'accueil la dernière annonce admin
//  (cf. AnnouncementRepository). Non bloquant, refermable d'un tap sur
//  la croix : l'id fermé est mémorisé pour ne pas réafficher la même.
//
//  La CATÉGORIE de l'annonce (kind) pilote l'icône, la couleur et le
//  libellé du badge :
//    - nouveaute  → étincelle, couleur accent
//    - promo      → flamme, couleur « warning » (or)
//    - info       → info, couleur « info » (bleu)
//    - maintenance→ clé, couleur « live » (rouge)
//
//  Si un lien est fourni, un bouton d'action (libellé `cta`, ou « Ouvrir »
//  par défaut) l'ouvre dans le navigateur. Tout le bandeau reste cliquable.
//
//  Couleurs/typo : uniquement AppColors / AppTextStyles (convention).
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/announcement_repository.dart';

/// Style visuel résolu depuis la catégorie d'une annonce.
class _KindStyle {
  const _KindStyle(this.color, this.icon, this.label);
  final Color color;
  final IconData icon;
  final String label; // '' = pas de badge (catégorie inconnue/vide)
}

/// Résout le style depuis la catégorie. Prend [AppLocalizations] en
/// paramètre (fourni par le build) pour que le libellé du badge suive
/// la langue active — « Info » réutilise la clé existante catInfo.
_KindStyle _styleFor(String kind, AppLocalizations l10n) {
  switch (kind) {
    case 'nouveaute':
      return _KindStyle(AppColors.accent, Icons.auto_awesome_rounded,
          l10n.announcementBadgeNew);
    case 'promo':
      return _KindStyle(AppColors.warning, Icons.local_fire_department_rounded,
          l10n.announcementBadgePromo);
    case 'info':
      return _KindStyle(AppColors.info, Icons.info_rounded, l10n.catInfo);
    case 'maintenance':
      return _KindStyle(AppColors.live, Icons.build_rounded,
          l10n.announcementBadgeMaintenance);
    default:
      return _KindStyle(AppColors.accent, Icons.campaign_rounded, '');
  }
}

/// Bandeau auto-géré : il va chercher l'annonce tout seul au montage,
/// ne s'affiche que s'il y en a une NON déjà fermée, et disparaît une
/// fois fermé. S'il n'y a rien : `SizedBox.shrink()` (zéro hauteur).
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  Announcement? _announcement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Announcement? a = await AnnouncementRepository.fetchLatest();
    if (a == null) return;
    // Ne pas réafficher une annonce déjà fermée par l'utilisateur.
    if (await AnnouncementRepository.isDismissed(a.id)) return;
    if (!mounted) return;
    setState(() => _announcement = a);
  }

  Future<void> _dismiss() async {
    final Announcement? a = _announcement;
    if (a == null) return;
    await AnnouncementRepository.dismiss(a.id);
    if (!mounted) return;
    setState(() => _announcement = null);
  }

  Future<void> _openLink() async {
    final Announcement? a = _announcement;
    if (a == null || a.url.isEmpty) return;
    final Uri? uri = Uri.tryParse(a.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // best-effort : un lien cassé ne doit pas faire planter l'accueil.
    }
  }

  @override
  Widget build(BuildContext context) {
    final Announcement? a = _announcement;
    if (a == null) return const SizedBox.shrink();

    final bool hasLink = a.url.isNotEmpty;
    final _KindStyle style = _styleFor(a.kind, context.l10n);
    final Color color = style.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: hasLink ? _openLink : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: color.withValues(alpha: 0.12),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Pastille catégorie.
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 12),
                  child: Icon(style.icon, color: color, size: 24),
                ),
                // Badge + titre + corps + bouton.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Badge catégorie (si connue).
                      if (style.label.isNotEmpty) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            style.label.toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      if (a.title.isNotEmpty)
                        Text(
                          a.title,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (a.title.isNotEmpty && a.body.isNotEmpty)
                        const SizedBox(height: 2),
                      if (a.body.isNotEmpty)
                        Text(
                          a.body,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      // Bouton d'action (si lien fourni).
                      if (hasLink) ...<Widget>[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _openLink,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              a.cta.isNotEmpty
                                  ? a.cta
                                  : context.l10n.announcementOpen,
                              style: AppTextStyles.button.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.voidSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Croix de fermeture.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  tooltip: MaterialLocalizations.of(context)
                      .closeButtonTooltip,
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  onPressed: _dismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
