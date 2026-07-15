// =========================================================
//  tv_rails_home_screen.dart — Template « IBO — Rails »
// =========================================================
//  Réplique de l'accueil « rails » d'IBO Player Pro : barre haute
//  (reload · profil · réglages · horloge) + héro à gauche + accès rapides
//  à droite + rangée d'icônes (Direct, Films, Séries, Catch-up, Recherche)
//  + rail de FAVORIS EN DIRECT (vraie donnée, LiveNowFavoritesRow).
//  COULEURS IDENTIQUES à IBO (violet #250030, tuiles #411C4C, focus #391A43
//  + liseré clair). SEUL le logo = SEVEN.
//
//  Réutilise des écrans + widgets EXISTANTS (aucune donnée inventée).
//  Aucun fichier cast/lecture/boot touché. 100 % télécommande.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../channels/presentation/widgets/live_now_favorites_row.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';

// ---- Palette IBO « rails » (HEX de la fiche mesurée) ----
const Color _rBgTop = Color(0xFF23002E); // fond haut (plus sombre)
const Color _rBg = Color(0xFF250030); // fond principal violet très sombre
const Color _rCard = Color(0xFF411C4C); // tuile au repos
const Color _rCardFocus = Color(0xFF391A43); // tuile au focus
const Color _rBorderFocus = Color(0xFFE9E4EC); // liseré clair (focus)
const Color _rText = Color(0xFFFFFFFF); // label/icône focus
const Color _rMuted = Color(0xFF999A9A); // label/icône repos
const Color _rTitle = Color(0xFFC9C0CC); // titres de rails
const Color _rPlay = Color(0xFF5C0404); // badge Play (rouge sombre)

class TvRailsHomeScreen extends StatelessWidget {
  const TvRailsHomeScreen({super.key});

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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[_rBgTop, _rBg],
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
                  // ---- Barre haute ----
                  Row(
                    children: <Widget>[
                      const TvLogo(width: 104),
                      const Spacer(),
                      _TopIcon(
                          icon: Icons.refresh_rounded,
                          onSelect: () => _open(context, const TvLiveScreen())),
                      const SizedBox(width: 10),
                      _TopIcon(
                          icon: Icons.person_outline_rounded,
                          onSelect: () =>
                              _open(context, const TvProfilesScreen())),
                      const SizedBox(width: 10),
                      _TopIcon(
                          icon: Icons.settings_outlined,
                          onSelect: () =>
                              _open(context, const TvSettingsScreen())),
                      const SizedBox(width: 18),
                      const _Clock(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ---- Zone héro (gauche) + accès rapides (droite) ----
                  Expanded(
                    flex: 5,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          flex: 66,
                          child: _Hero(
                            autofocus: true,
                            onSelect: () => _open(context, const TvLiveScreen()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 32,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('Accès rapide',
                                  style: TvTokens.ui(TvDimens.label,
                                      weight: FontWeight.w600, color: _rTitle)),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _NavTile(
                                  icon: Icons.star_rounded,
                                  label: 'Favoris',
                                  onSelect: () =>
                                      _open(context, const TvLiveScreen()),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _NavTile(
                                  icon: Icons.grid_view_rounded,
                                  label: 'Guide',
                                  onSelect: () => _open(
                                      context, const TvGuideGridScreen()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ---- Rangée d'icônes de navigation ----
                  SizedBox(
                    height: 132,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _NavTile(
                            icon: Icons.live_tv_rounded,
                            label: 'Direct',
                            onSelect: () => _open(context, const TvLiveScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.movie_rounded,
                            label: 'Films',
                            onSelect: () => _open(context, const TvFilmsScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.video_library_rounded,
                            label: 'Séries',
                            onSelect: () =>
                                _open(context, const TvSeriesScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.replay_rounded,
                            label: 'Catch-up',
                            onSelect: () =>
                                _open(context, const TvRecordingsScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.search_rounded,
                            label: 'Recherche',
                            onSelect: () =>
                                _open(context, const TvSearchScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.dashboard_customize_rounded,
                            label: 'Templates',
                            onSelect: () =>
                                _open(context, const TvHomeTemplateScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ---- Rail FAVORIS EN DIRECT (vraie donnée) ----
                  Text('Favoris en direct',
                      style: TvTokens.ui(TvDimens.title,
                          weight: FontWeight.w600, color: _rTitle)),
                  const SizedBox(height: 8),
                  const SizedBox(height: 168, child: LiveNowFavoritesRow()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icône de la barre haute (reload / profil / réglages).
class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onSelect});
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: focused ? _rCardFocus : Colors.transparent,
            shape: BoxShape.circle,
            border: focused
                ? Border.all(color: _rBorderFocus, width: 2)
                : null,
          ),
          child: Icon(icon, size: 28, color: focused ? _rText : _rMuted),
        );
      },
    );
  }
}

/// Horloge 24 h (mise à jour douce).
class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    return Text('$hh:$mm',
        style: TvTokens.ui(TvDimens.title, weight: FontWeight.w500, color: _rText));
  }
}

/// Héro : grande zone « Direct » avec badge Play rouge.
class _Hero extends StatelessWidget {
  const _Hero({required this.onSelect, this.autofocus = false});
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF3A2145), Color(0xFF2A1233)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? _rBorderFocus : _rCard,
              width: focused ? 2 : 1,
            ),
          ),
          child: Stack(
            children: <Widget>[
              Center(
                child: Icon(Icons.live_tv_rounded,
                    size: 92, color: focused ? _rText : _rMuted),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: _rPlay,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.play_arrow_rounded,
                          size: 22, color: _rText),
                      const SizedBox(width: 6),
                      Text('Direct',
                          style: TvTokens.ui(TvDimens.body,
                              weight: FontWeight.w700, color: _rText)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tuile de navigation (icône + label), style IBO rails.
class _NavTile extends StatelessWidget {
  const _NavTile({
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
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? _rCardFocus : _rCard,
            borderRadius: BorderRadius.circular(10),
            border: focused
                ? Border.all(color: _rBorderFocus, width: 2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 40, color: focused ? _rText : _rMuted),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.label,
                        weight: FontWeight.w600,
                        color: focused ? _rText : _rMuted)),
              ),
            ],
          ),
        );
      },
    );
  }
}
