// =========================================================
//  tv_launcher_home_screen.dart — Template « Grandes tuiles » (façon IBO)
// =========================================================
//  Accueil alternatif, choisi via le sélecteur de templates : une GRANDE
//  tuile héro « Direct » + un cluster 2×2 (Films, Séries, Guide, Recherche)
//  + une colonne de raccourcis (Sources, Réglages, Templates, Quitter).
//  Simple, direct, 100 % télécommande — « comme à la maison ».
//
//  N'invente aucune donnée : chaque tuile ouvre un écran EXISTANT. Aucun
//  fichier cast/lecture/boot touché. Style Maison Noir (or/obsidienne).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';
import 'tv_sources_screen.dart';

class TvLauncherHomeScreen extends StatelessWidget {
  const TvLauncherHomeScreen({super.key});

  void _open(BuildContext c, Widget screen) {
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _confirmExit(BuildContext c) async {
    final bool? quit = await showDialog<bool>(
      context: c,
      builder: (BuildContext d) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Text('Quitter SEVEN ?',
            style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text('Annuler', style: TvTokens.ui(TvDimens.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Quitter',
                style: TvTokens.ui(TvDimens.body, color: TvTokens.goldBright)),
          ),
        ],
      ),
    );
    if (quit == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: TvShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Barre haute : logo + marque
            Row(
              children: <Widget>[
                const TvLogo(width: 118),
                const Spacer(),
                Text('SEVEN',
                    style: TvTokens.ui(TvDimens.title,
                        weight: FontWeight.w700, color: TvTokens.gold, spacing: 4)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ---- HÉRO : Direct ----
                  Expanded(
                    flex: 5,
                    child: _HeroTile(
                      icon: Icons.live_tv_rounded,
                      label: 'Direct',
                      autofocus: true,
                      onSelect: () => _open(context, const TvLiveScreen()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // ---- Cluster 2×2 ----
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: _SquareTile(
                                  icon: Icons.movie_rounded,
                                  label: 'Films',
                                  onSelect: () => _open(context, const TvFilmsScreen()),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _SquareTile(
                                  icon: Icons.video_library_rounded,
                                  label: 'Séries',
                                  onSelect: () => _open(context, const TvSeriesScreen()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: _SquareTile(
                                  icon: Icons.people_alt_rounded,
                                  label: 'Compte',
                                  onSelect: () =>
                                      _open(context, const TvProfilesScreen()),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _SquareTile(
                                  icon: Icons.swap_horiz_rounded,
                                  label: 'Changer la source',
                                  onSelect: () =>
                                      _open(context, const TvSourcesScreen()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // ---- Colonne de raccourcis ----
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: _RowButton(
                            icon: Icons.grid_view_rounded,
                            label: 'Guide TV',
                            onSelect: () =>
                                _open(context, const TvGuideGridScreen()),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _RowButton(
                            icon: Icons.settings_rounded,
                            label: 'Réglages',
                            onSelect: () => _open(context, const TvSettingsScreen()),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _RowButton(
                            icon: Icons.dashboard_customize_rounded,
                            label: 'Changer les templates',
                            onSelect: () =>
                                _open(context, const TvHomeTemplateScreen()),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _RowButton(
                            icon: Icons.power_settings_new_rounded,
                            label: 'Quitter',
                            onSelect: () => _confirmExit(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Décoration commune d'une tuile (repos vs focus or).
Widget _tileBox({required bool focused, required Widget child}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: focused ? TvTokens.sel : TvTokens.card,
      borderRadius: BorderRadius.circular(TvTokens.rCard),
      border: Border.all(
        color: focused ? TvTokens.goldBright : TvTokens.hairline,
        width: focused ? 2 : 1,
      ),
      boxShadow: focused
          ? <BoxShadow>[
              BoxShadow(
                color: TvTokens.gold.withValues(alpha: 0.28),
                blurRadius: 32,
                spreadRadius: -8,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    ),
    child: child,
  );
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return _tileBox(
          focused: focused,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon,
                  size: 92, color: focused ? TvTokens.goldBright : TvTokens.gold),
              const SizedBox(height: 18),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(TvDimens.displayS,
                      weight: FontWeight.w700, color: TvTokens.text)),
            ],
          ),
        );
      },
    );
  }
}

class _SquareTile extends StatelessWidget {
  const _SquareTile({
    required this.icon,
    required this.label,
    required this.onSelect,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return _tileBox(
          focused: focused,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon,
                  size: 52, color: focused ? TvTokens.goldBright : TvTokens.gold),
              const SizedBox(height: 12),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(TvDimens.title,
                      weight: FontWeight.w600, color: TvTokens.text)),
            ],
          ),
        );
      },
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.label,
    required this.onSelect,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return _tileBox(
          focused: focused,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    size: 30,
                    color: focused ? TvTokens.goldBright : TvTokens.gold),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.body,
                          weight: FontWeight.w600, color: TvTokens.text)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
