// =========================================================
//  affiliate_card.dart — Carte d'affiliation discrète (accueil)
// =========================================================
//  Affiche AU PLUS UNE campagne (cf. CampaignRepository.pickForHome) en
//  carte fine et refermable : vignette + titre + petit bouton CTA
//  (« Acheter »…). Le clic ouvre le lien d'affiliation NATIVEMENT sur
//  Android (Intent.ACTION_VIEW via url_launcher) et compte le clic ;
//  l'affichage compte une impression (une par session).
//
//  Règles maison :
//    - abonné PAYANT = zéro pub → la carte ne se monte jamais ;
//    - rien à montrer → SizedBox.shrink() (zéro hauteur, zéro coût) ;
//    - fermeture mémorisée par campagne (croix) ;
//    - temps réel : une campagne publiée/retirée au panel apparaît ou
//      disparaît en direct (signal `revision`).
//  Aucune dépendance au cast.
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../subscription/data/subscription_state.dart';
import '../data/campaign_repository.dart';

class AffiliateCard extends StatefulWidget {
  const AffiliateCard({super.key});

  @override
  State<AffiliateCard> createState() => _AffiliateCardState();
}

class _AffiliateCardState extends State<AffiliateCard> {
  Campaign? _campaign;

  @override
  void initState() {
    super.initState();
    _load();
    CampaignRepository.revision.addListener(_load);
  }

  @override
  void dispose() {
    CampaignRepository.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // « Acheter sans pubs » : un abonné payant ne voit aucune campagne.
    if (SubscriptionState.instance.status == SubscriptionStatus.paid) {
      if (mounted && _campaign != null) setState(() => _campaign = null);
      return;
    }
    final List<Campaign> all = await CampaignRepository.fetchAll();
    final Set<int> dismissed = await CampaignRepository.dismissedIds();
    if (!mounted) return;
    final Campaign? pick =
        CampaignRepository.pickForHome(all, dismissed: dismissed);
    if (pick?.id != _campaign?.id) setState(() => _campaign = pick);
    if (pick != null) CampaignRepository.trackImpression(pick.id);
  }

  Future<void> _open() async {
    final Campaign? c = _campaign;
    if (c == null) return;
    CampaignRepository.trackClick(c.id);
    final Uri? uri = Uri.tryParse(c.targetUrl);
    if (uri == null) return;
    try {
      // externalApplication = Intent.ACTION_VIEW : navigateur ou app
      // partenaire (Amazon, boutique…) si elle est installée.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // best-effort : un lien cassé ne doit pas faire planter l'accueil.
    }
  }

  Future<void> _dismiss() async {
    final Campaign? c = _campaign;
    if (c == null) return;
    await CampaignRepository.dismiss(c.id);
    if (!mounted) return;
    setState(() => _campaign = null);
  }

  @override
  Widget build(BuildContext context) {
    final Campaign? c = _campaign;
    if (c == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.maisonSurfaceHigh.withValues(alpha: 0.6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: <Widget>[
                // Vignette (ou icône shopping si pas d'image).
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: c.imageUrl.isEmpty
                        ? Container(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            child: Icon(
                              Icons.shopping_bag_rounded,
                              color: AppColors.accent,
                              size: 22,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: c.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 132,
                            memCacheHeight: 132,
                            fadeInDuration:
                                const Duration(milliseconds: 150),
                            errorWidget: (_, __, ___) => Container(
                              color:
                                  AppColors.accent.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.shopping_bag_rounded,
                                color: AppColors.accent,
                                size: 22,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                // Titre + texte, volontairement petits (discrétion).
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (c.title.isNotEmpty)
                        Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (c.body.isNotEmpty)
                        Text(
                          c.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Petit bouton CTA (« Acheter »…).
                GestureDetector(
                  onTap: _open,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c.cta.isNotEmpty ? c.cta : context.l10n.announcementOpen,
                      style: AppTextStyles.button.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.voidSurface,
                      ),
                    ),
                  ),
                ),
                // Croix de fermeture.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  splashRadius: 16,
                  tooltip:
                      MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
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
