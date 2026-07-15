// =========================================================
//  tv_launcher_home_screen.dart — Template « Grandes tuiles » (IBO grille)
// =========================================================
//  Réplique FIDÈLE de l'accueil « grille » d'IBO Player Pro : grande tuile
//  héro « Direct » + cluster 2×2 (Films, Séries, Compte, Changer la source)
//  + colonne (Guide, Réglages, Templates, Quitter) + pilule verte « Regarder ».
//  COULEURS IDENTIQUES à IBO (fond quasi-noir, tuiles bordeaux, liseré blanc
//  au focus, texte/icônes blancs, bouton vert). SEUL le logo = SEVEN.
//
//  N'invente aucune donnée : chaque tuile ouvre un écran EXISTANT. Aucun
//  fichier cast/lecture/boot touché. 100 % télécommande (TvFocusBuilder).
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
import 'tv_sources_screen.dart';

// ---- Palette IBO (grille) — couleurs identiques à l'original ----
const Color _iboBg = Color(0xFF0A0A0A); // fond quasi-noir
const Color _iboTile = Color(0xFF7A1F1F); // tuile bordeaux au repos
const Color _iboTileFocus = Color(0xFF8E2626); // tuile bordeaux au focus
const Color _iboText = Color(0xFFFFFFFF); // labels + icônes (blancs)
const Color _iboGreenA = Color(0xFF29C46B); // pilule « Regarder » (vert)
const Color _iboGreenB = Color(0xFF1EA65A);

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
      child: ColoredBox(
        color: _iboBg,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TvDimens.safeH,
                vertical: TvDimens.safeV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Logo SEVEN centré (seul élément de marque changé).
                  const Center(child: TvLogo(width: 132)),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // ---- HÉRO : Direct (grande tuile) ----
                        Expanded(
                          flex: 5,
                          child: _HeroTile(
                            icon: Icons.live_tv_rounded,
                            label: 'Live TV',
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
                                        onSelect: () =>
                                            _open(context, const TvFilmsScreen()),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _SquareTile(
                                        icon: Icons.video_library_rounded,
                                        label: 'Séries',
                                        onSelect: () => _open(
                                            context, const TvSeriesScreen()),
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
                                        onSelect: () => _open(
                                            context, const TvProfilesScreen()),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _SquareTile(
                                        icon: Icons.swap_horiz_rounded,
                                        label: 'Changer la source',
                                        onSelect: () => _open(
                                            context, const TvSourcesScreen()),
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
                                  icon: Icons.settings_rounded,
                                  label: 'Réglages',
                                  onSelect: () =>
                                      _open(context, const TvSettingsScreen()),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: _RowButton(
                                  icon: Icons.grid_view_rounded,
                                  label: 'Guide TV',
                                  onSelect: () => _open(
                                      context, const TvGuideGridScreen()),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: _RowButton(
                                  icon: Icons.dashboard_customize_rounded,
                                  label: 'Changer les templates',
                                  onSelect: () => _open(
                                      context, const TvHomeTemplateScreen()),
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
                  const SizedBox(height: 16),
                  // ---- Pilule verte « Regarder » (Play Video) ----
                  Center(
                    child: _PlayPill(
                      onSelect: () => _open(context, const TvLiveScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Décoration commune d'une tuile IBO (bordeaux + liseré blanc au focus).
Widget _tileBox({required bool focused, required Widget child}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: focused ? _iboTileFocus : _iboTile,
      borderRadius: BorderRadius.circular(TvTokens.rCard),
      border: Border.all(
        color: focused ? _iboText : Colors.transparent,
        width: focused ? 3 : 0,
      ),
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
              Icon(icon, size: 92, color: _iboText),
              const SizedBox(height: 18),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(TvDimens.displayS,
                      weight: FontWeight.w700, color: _iboText)),
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
              Icon(icon, size: 48, color: _iboText),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.titleS,
                        weight: FontWeight.w600, color: _iboText)),
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 28, color: _iboText),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.body,
                          weight: FontWeight.w600, color: _iboText)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pilule verte « Regarder » (Play Video) — accent d'IBO.
class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.onSelect});
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[_iboGreenA, _iboGreenB],
            ),
            borderRadius: BorderRadius.circular(999),
            border:
                focused ? Border.all(color: _iboText, width: 2) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.play_arrow_rounded, size: 26, color: _iboText),
              const SizedBox(width: 8),
              Text('Regarder',
                  style: TvTokens.ui(TvDimens.body,
                      weight: FontWeight.w700, color: _iboText)),
            ],
          ),
        );
      },
    );
  }
}
