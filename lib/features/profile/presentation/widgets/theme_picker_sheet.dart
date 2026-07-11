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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: SafeArea(
        top: false,
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
            const SizedBox(height: 20),
            // Grille de pastilles
            Wrap(
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
          ],
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
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.textPrimary,
                      size: 26,
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              accentThemeLabel(context, theme),
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
