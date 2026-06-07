// =========================================================
//  announcement_banner.dart — Bandeau « message à tous »
// =========================================================
//  Affiche en haut de l'accueil la dernière annonce admin
//  (cf. AnnouncementRepository). Non bloquant, refermable d'un tap sur
//  la croix : l'id fermé est mémorisé pour ne pas réafficher la même.
//
//  Si un lien est fourni dans l'annonce, tout le bandeau devient
//  cliquable et l'ouvre dans le navigateur.
//
//  Couleurs/typo : uniquement AppColors / AppTextStyles (convention).
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/announcement_repository.dart';

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
              color: AppColors.accent.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Pastille mégaphone.
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 12),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: AppColors.accent,
                    size: 24,
                  ),
                ),
                // Titre + corps.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
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
                      if (hasLink) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          a.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 11,
                            color: AppColors.accent,
                            decoration: TextDecoration.underline,
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
