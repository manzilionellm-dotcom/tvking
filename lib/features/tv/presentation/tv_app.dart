// =========================================================
//  tv_app.dart — Racine de DeFew TV (MaterialApp 10-foot)
// =========================================================
//  Thème sombre, typo agrandie (§6-7). L'accueil pose le squelette de
//  navigation D-pad (rail gauche focusable) — les écrans Live / Guide /
//  Films / Séries / Recherche viendront se brancher dessus (BUILD_ORDER
//  5→9), en réutilisant les briques data du mobile.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_live_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.textPrimary,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'DeFew TV',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Coupe TOUT effet tactile (hover/splash souris) — D-pad only.
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
      ),
      home: const TvHomeScreen(),
    );
  }
}

/// Destinations de la navigation principale (buckets §8 home).
enum TvDest { live, films, series, guide, search, settings }

extension on TvDest {
  String get label {
    switch (this) {
      case TvDest.live:
        return 'Direct';
      case TvDest.films:
        return 'Films';
      case TvDest.series:
        return 'Séries';
      case TvDest.guide:
        return 'Guide';
      case TvDest.search:
        return 'Recherche';
      case TvDest.settings:
        return 'Réglages';
    }
  }

  IconData get icon {
    switch (this) {
      case TvDest.live:
        return Icons.live_tv_rounded;
      case TvDest.films:
        return Icons.movie_rounded;
      case TvDest.series:
        return Icons.video_library_rounded;
      case TvDest.guide:
        return Icons.grid_view_rounded;
      case TvDest.search:
        return Icons.search_rounded;
      case TvDest.settings:
        return Icons.settings_rounded;
    }
  }
}

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  TvDest _selected = TvDest.live;

  @override
  Widget build(BuildContext context) {
    return TvShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ----- Rail de navigation (gauche) -----
          SizedBox(
            width: 240,
            child: _NavRail(
              selected: _selected,
              onSelect: (TvDest d) => setState(() => _selected = d),
            ),
          ),
          const SizedBox(width: TvDimens.gutter),
          // ----- Panneau de contenu (placeholder par destination) -----
          Expanded(child: _ContentPanel(dest: _selected)),
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelect});

  final TvDest selected;
  final ValueChanged<TvDest> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          child: Text(
            'DeFew TV',
            style: TextStyle(
              fontSize: TvDimens.headline,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (int i = 0; i < TvDest.values.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NavItem(
                    dest: TvDest.values[i],
                    selected: TvDest.values[i] == selected,
                    // Focus initial sur le 1er item (Direct).
                    autofocus: i == 0,
                    onSelect: () => onSelect(TvDest.values[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final TvDest dest;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        // Au focus : fond clair + contenu sombre (pattern TiviMate).
        final Color bg = focused
            ? AppColors.textPrimary
            : (selected ? AppColors.surfaceHigh : Colors.transparent);
        final Color fg = focused
            ? AppColors.background
            : (selected ? AppColors.textPrimary : AppColors.textSecondary);
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(dest.icon, color: fg, size: 26),
              const SizedBox(width: 14),
              Text(
                dest.label,
                style: TextStyle(
                  fontSize: TvDimens.title,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.dest});

  final TvDest dest;

  @override
  Widget build(BuildContext context) {
    // « Direct » et « Réglages » sont branchés ; les autres buckets
    // arrivent (BUILD_ORDER 6-9).
    if (dest == TvDest.live) return const TvLiveScreen();
    if (dest == TvDest.settings) return const TvSettingsScreen();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          dest.label,
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Écran « ${dest.label} » — en construction.',
          style: TextStyle(
            fontSize: TvDimens.body,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
