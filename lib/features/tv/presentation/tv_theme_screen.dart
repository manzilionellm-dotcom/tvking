// =========================================================
//  tv_theme_screen.dart — Sélecteur de thème (TV, 10-foot / D-pad)
// =========================================================
//  Version TV du sélecteur de couleur d'accent du mobile : la MÊME
//  palette premium (119 teintes, cf. accent_controller.dart) + le mode
//  IMMERSIF « une couleur par jour ». Navigation à la télécommande
//  (TvFocusBuilder) ; la pastille focalisée est ramenée dans la vue.
//  Le changement recolore INSTANTANÉMENT toute l'app TV (AccentController
//  est branché à la racine de tv_app.dart).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/accent_controller.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvThemeScreen extends StatefulWidget {
  const TvThemeScreen({super.key});

  @override
  State<TvThemeScreen> createState() => _TvThemeScreenState();
}

class _TvThemeScreenState extends State<TvThemeScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: AccentController.instance,
        builder: (BuildContext context, _) {
          final bool daily = AccentController.instance.isDaily;
          final String currentId = AccentController.instance.current.id;
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.themeChooseTitle,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.themeChooseSub,
                  style: const TextStyle(fontSize: 16, color: TvTokens.mutedDim),
                ),
                const SizedBox(height: 20),

                // ----- Mode IMMERSIF : une couleur par jour -----
                _ImmersiveTile(active: daily),
                const SizedBox(height: 18),

                // ----- Grille premium (119 teintes), défilante -----
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 22,
                      children: <Widget>[
                        for (final AccentTheme t in kAccentThemes)
                          _TvSwatch(
                            key: ValueKey<String>('sw_${t.id}'),
                            theme: t,
                            selected: !daily && t.id == currentId,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Grande tuile « Thème immersif » (auto-focus à l'ouverture).
class _ImmersiveTile extends StatelessWidget {
  const _ImmersiveTile({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: true,
      scale: TvFocusScale.large,
      onSelect: () => AccentController.instance.enableDaily(),
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? TvTokens.onGold : TvTokens.goldBright;
        return Container(
          width: 900,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
              color: active && !focused ? TvTokens.goldBright : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: fg, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Thème immersif',
                      style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Une couleur premium qui change chaque heure',
                      style: TextStyle(
                        fontSize: 15,
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                active ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: fg,
                size: 30,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Une pastille de couleur focalisable ; ramenée dans la vue au focus.
class _TvSwatch extends StatelessWidget {
  const _TvSwatch({super.key, required this.theme, required this.selected});

  final AccentTheme theme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: () => AccentController.instance.select(theme),
      builder: (BuildContext context, bool focused) {
        if (focused) {
          // Ramène la pastille focalisée au centre de la zone défilante
          // (après le frame courant : ensureVisible pendant build est interdit).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }
          });
        }
        final Color ring = focused
            ? TvTokens.text
            : (selected ? theme.bright : Colors.transparent);
        return SizedBox(
          width: 128,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[theme.bright, theme.accent, theme.muted],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: focused ? 4 : 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: theme.accent.withValues(alpha: focused ? 0.65 : 0.4),
                      blurRadius: focused ? 20 : 12,
                      spreadRadius: focused ? 2 : 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: TvTokens.text, size: 34)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                theme.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: focused ? TvTokens.text : TvTokens.mutedDim,
                  fontWeight: focused || selected
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
