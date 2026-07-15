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

// ---- Palette IBO (grille) — HEX échantillonnés sur le mockup officiel ----
// Fond : bleu-nuit très sombre en haut-gauche → halo chaud brun/rouge en
// bas-droite (pas un noir plat). Tuiles bordeaux #6B0B15 (héro + cluster).
// Boutons de la colonne droite : fond maroon sombre DIFFÉRENT + bordure.
const Color _iboBgA = Color(0xFF010010); // fond haut-gauche (quasi noir bleuté)
const Color _iboBgB = Color(0xFF0D0B20); // fond centre (bleu-nuit)
const Color _iboBgGlow = Color(0xFF2E150C); // halo chaud bas-droite
const Color _iboTile = Color(0xFF6B0B15); // surface tuile (héro + cluster)
const Color _iboColBtn = Color(0xFF362119); // fond bouton colonne
const Color _iboColBtnBorder = Color(0xFF432819); // bordure bouton colonne
const Color _iboText = Color(0xFFFFFFFF); // icônes + labels (blancs)

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
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[_iboBgA, _iboBgB, _iboBgGlow],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tuile bordeaux (héro + cluster) : surface #6B0B15 constante, liseré BLANC
/// au focus (pas de changement de couleur — conforme au mockup IBO).
Widget _tileBox({required bool focused, required Widget child}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _iboTile,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: focused ? _iboText : Colors.transparent,
        width: focused ? 3 : 0,
      ),
    ),
    child: child,
  );
}

/// Bouton de la colonne droite : fond maroon sombre #362119 + bordure
/// #432819 ; liseré blanc au focus.
Widget _colBtnBox({required bool focused, required Widget child}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: _iboColBtn,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: focused ? _iboText : _iboColBtnBorder,
        width: focused ? 3 : 1.5,
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
        return _colBtnBox(
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

