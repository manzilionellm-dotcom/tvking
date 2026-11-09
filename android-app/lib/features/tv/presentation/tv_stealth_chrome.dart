// Chrome de l'accueil : toutes les informations viennent du hub existant.
// Pas de photographie, de météo, de certification ou d'abonnement inventé.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_stealth_home.dart';

class TvStealthHeader extends StatelessWidget {
  const TvStealthHeader({
    super.key,
    this.logo,
    required this.profileName,
    required this.profileIcon,
    required this.profileColor,
    required this.onProfile,
    required this.onSearch,
    required this.searchLabel,
    required this.time,
    required this.date,
    required this.networkIcon,
    this.greeting = '',
    this.status = '',
    this.avatar,
  });
  final Widget? logo;
  final String profileName, searchLabel, time, date, greeting, status;
  final IconData profileIcon, networkIcon;
  final Color profileColor;
  final VoidCallback onProfile, onSearch;
  // Le catalogue actuel possède des icônes. Cette entrée accepte une vraie
  // photo si le modèle utilisateur en fournit une à l'avenir.
  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 1000;
          final profile = TvFocusBuilder(
            onSelect: onProfile,
            showGlow: false,
            builder: (context, focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.stealthGlass,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                border: Border.all(
                  color: AppColors.stealthPlatinum.withValues(
                    alpha: focused ? 1 : .18,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: profileColor.withValues(alpha: .18),
                    foregroundImage: avatar,
                    child: avatar == null
                        ? Icon(profileIcon, color: profileColor, size: 24)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          profileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.stealthBody,
                        ),
                        if (status.isNotEmpty)
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.stealthCaption,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: compact ? 110 : 130,
                    child: logo ??
                        Text(
                          context.l10n.tvStealthWordmark,
                          style: AppTextStyles.stealthBrand,
                        ),
                  ),
                  const SizedBox(width: 16),
                  if (!compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              AppColors.stealthPlatinum.withValues(alpha: .3),
                        ),
                      ),
                      child: Text(
                        context.l10n.tvStealthPremierBadge,
                        style: AppTextStyles.stealthCaption.copyWith(
                          color: AppColors.stealthPlatinum,
                        ),
                      ),
                    ),
                  const Spacer(),
                  StealthAction(
                    label: searchLabel,
                    icon: Icons.search_rounded,
                    onSelect: onSearch,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: compact ? 160 : 225, child: profile),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.stealthCaption,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(networkIcon, size: 18, color: AppColors.stealthMuted),
                  const SizedBox(width: 12),
                  Text(
                    time,
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.stealthBody,
                  ),
                  const SizedBox(width: 12),
                  Text(date, style: AppTextStyles.stealthCaption),
                ],
              ),
            ],
          );
        },
      );
}

class TvStealthFooter extends StatelessWidget {
  const TvStealthFooter({
    super.key,
    required this.activationLabel,
    required this.activationCode,
    required this.status,
    required this.statusColor,
    this.source = '',
  });
  final String activationLabel, activationCode, status, source;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.stealthPlatinum.withValues(alpha: .12),
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Flexible(
              flex: 3,
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  Text(activationLabel, style: AppTextStyles.stealthCaption),
                  Text(
                    activationCode,
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.stealthCode,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (source.isNotEmpty)
              Expanded(
                flex: 2,
                child: Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.stealthCaption,
                ),
              )
            else
              const Spacer(),
            if (status.isNotEmpty) ...<Widget>[
              const SizedBox(width: 16),
              Flexible(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.circle, size: 6, color: statusColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.stealthCaption.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}
