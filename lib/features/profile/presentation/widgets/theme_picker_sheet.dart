// =========================================================
//  theme_picker_sheet.dart — Sélecteur de couleur d'accent
// =========================================================
//  Bottom sheet ouvert depuis le bouton « Thème » (Profil). Affiche
//  une grille de pastilles de couleur ; un tap applique le thème
//  INSTANTANÉMENT (AccentController notifie → la racine se reconstruit
//  → toute l'app se recolore). La feuille reste ouverte pour que le
//  client puisse essayer plusieurs couleurs et voir le résultat en
//  direct ; il ferme quand il a choisi.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/accent_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Libellé localisé d'un thème d'accent.
///
/// Les thèmes du catalogue (accent_controller.dart) portent un `id`
/// stable + un `label` français : on mappe ici l'`id` vers la clé de
/// traduction `accentX`, et `label` sert de REPLI documenté si un
/// nouvel id n'a pas encore sa clé (l'app affiche alors le français
/// plutôt que de planter ou de montrer un id technique).
String _accentLabel(BuildContext context, AccentTheme theme) {
  switch (theme.id) {
    case 'champagne':
      return context.l10n.accentChampagne;
    case 'ember':
      return context.l10n.accentEmber;
    case 'ocean':
      return context.l10n.accentOcean;
    case 'emerald':
      return context.l10n.accentEmerald;
    case 'violet':
      return context.l10n.accentViolet;
    case 'gold':
      return context.l10n.accentGold;
    case 'turquoise':
      return context.l10n.accentTurquoise;
    case 'rose':
      return context.l10n.accentRose;
    case 'coral':
      return context.l10n.accentCoral;
    case 'indigo':
      return context.l10n.accentIndigo;
    case 'lime':
      return context.l10n.accentLime;
    case 'remote':
      return context.l10n.accentCustom;
    default:
      return theme.label; // repli : libellé français du catalogue
  }
}

/// Ouvre le sélecteur de thème.
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends StatefulWidget {
  const _ThemePickerSheet();

  @override
  State<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<_ThemePickerSheet> {
  @override
  Widget build(BuildContext context) {
    final String currentId = AccentController.instance.current.id;
    // La palette premium compte 100+ teintes : on borne la feuille à ~82 %
    // de l'écran et on rend la GRILLE défilante (titre + sous-titre fixes).
    final double maxH = MediaQuery.of(context).size.height * 0.82;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Poignée
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.l10n.themeChooseTitle,
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.themeChooseSub,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              // Mode IMMERSIF — une couleur premium différente chaque jour.
              _ImmersiveTile(
                active: AccentController.instance.isDaily,
                onTap: () async {
                  await AccentController.instance.enableDaily();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 16),
              // Grille de pastilles — DÉFILANTE (catalogue premium 100+).
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      for (final AccentTheme t in kAccentThemes)
                        _Swatch(
                          theme: t,
                          selected: t.id == currentId,
                          onTap: () async {
                            await AccentController.instance.select(t);
                            // setState local pour rafraîchir l'anneau de
                            // sélection dans la feuille elle-même.
                            if (mounted) setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une pastille colorée + libellé. Anneau ivoire quand sélectionnée.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AccentTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[theme.bright, theme.accent, theme.muted],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? AppColors.textPrimary
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: AppColors.textPrimary,
                      size: 26,
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              _accentLabel(context, theme),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 10,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuile « Thème immersif » : une couleur premium différente chaque jour
/// (rotation automatique sur les 100+ teintes). Liseré d'accent quand actif.
class _ImmersiveTile extends StatelessWidget {
  const _ImmersiveTile({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppColors.accent.withValues(alpha: 0.7)
                : AppColors.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Thème immersif',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Une couleur premium différente chaque jour',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              active
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: active ? AppColors.accent : AppColors.textTertiary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
