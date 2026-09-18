// =========================================================
//  tv_rails_home_screen.dart — Template « IBO — Rails »
// =========================================================
//  Réplique de l'accueil « rails » d'IBO Player Pro : barre haute
//  (reload · profil · réglages · horloge) + héro à gauche + accès rapides
//  à droite + rangée d'icônes (Direct, Films, Séries, Catch-up, Recherche)
//  + rail de FAVORIS EN DIRECT (vraie donnée, rail TV natif).
//  COULEURS IDENTIQUES à IBO (violet #250030, tuiles #411C4C, focus #391A43
//  + liseré clair). SEUL le logo = SEVEN.
//
//  Réutilise des écrans + widgets EXISTANTS (aucune donnée inventée).
//  Le rail de favoris est 100 % TV natif : au tap → TvPlayerScreen
//  (ExoPlayer/Media3), JAMAIS le lecteur mobile (media_kit) — la
//  compilation TV ne doit importer aucun fichier media_kit.
//  Aucun fichier cast/lecture/boot touché. 100 % télécommande.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_developer_mode.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_memory_guard.dart';
import '../core/tv_tokens.dart';
// RestartWidget : le vrai « rechargement logiciel » de l'app (source +
// abonnement re-synchronisés, accueil reconstruit) — pour le bouton ⟳.
import 'tv_app.dart' show RestartWidget, showExitDialog;
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_preview.dart';
import 'tv_live_screen.dart';
import 'tv_player_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_screensaver.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';

// ---- Palette « rails » PREMIUM (violet conservé, éclairages néon) ----
// Base violette de l'identité du template + LUMIÈRES futuristes : liseré
// dégradé, halo néon au focus, bascule de teinte à l'APPUI. Les surfaces ne
// sont plus des aplats mais des dégradés subtils (profondeur).
const Color _rBgTop = Color(0xFF1B0024); // fond haut (plus sombre)
const Color _rBg = Color(0xFF250030); // fond principal violet très sombre
const Color _rCardA = Color(0xFF462152); // tuile repos — haut du dégradé
const Color _rCardB = Color(0xFF31123D); // tuile repos — bas du dégradé
const Color _rFocusA = Color(0xFF5E2C74); // tuile focus — haut (plus lumineux)
const Color _rFocusB = Color(0xFF3C1650); // tuile focus — bas
const Color _rPressA = Color(0xFF7C3EA0); // APPUI : la teinte BASCULE
const Color _rPressB = Color(0xFF4A1C66); // (violet électrique, retour visuel)
const Color _rNeon = Color(0xFFB26CFF); // lumière néon (halo/glow focus)
const Color _rNeonPress = Color(0xFF7DE2FF); // lumière d'APPUI (cyan électrique)
const Color _rBorderFocus = Color(0xFFEADCFF); // liseré clair (focus)
const Color _rSheen = Color(0x33FFFFFF); // filet lumineux haut de tuile
const Color _rText = Color(0xFFFFFFFF); // label/icône focus
const Color _rMuted = Color(0xFFA79FB0); // label/icône repos
const Color _rTitle = Color(0xFFCFC4D6); // titres de rails
const Color _rPlay = Color(0xFF5C0404); // badge Play (rouge sombre)

/// Coque de tuile PREMIUM partagée par toutes les surfaces du template :
///   • dégradé de profondeur (jamais un aplat) + filet lumineux en haut ;
///   • focus : liseré clair + HALO NÉON (lumière futuriste, douce) ;
///   • APPUI (OK enfoncé / doigt posé) : la teinte BASCULE en violet
///     électrique + halo cyan — la demande « ça change de couleur quand on
///     appuie ». AnimatedContainer 160 ms easeOutCubic : zoom et couleurs
///     glissent, rien ne « saute ».
Widget _railsShell({
  required bool focused,
  required bool pressed,
  required Widget child,
  double radius = 14,
  AlignmentGeometry? alignment,
}) {
  final Color top = pressed ? _rPressA : (focused ? _rFocusA : _rCardA);
  final Color bottom = pressed ? _rPressB : (focused ? _rFocusB : _rCardB);
  final Color halo = pressed ? _rNeonPress : _rNeon;
  return AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    alignment: alignment,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[top, bottom],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: pressed
            ? _rNeonPress
            : (focused ? _rBorderFocus : _rSheen),
        width: focused || pressed ? 2 : 1,
      ),
      boxShadow: (focused || pressed)
          ? <BoxShadow>[
              BoxShadow(
                color: halo.withValues(alpha: pressed ? 0.55 : 0.38),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ]
          : null,
    ),
    child: child,
  );
}

class TvRailsHomeScreen extends StatefulWidget {
  const TvRailsHomeScreen({super.key});

  @override
  State<TvRailsHomeScreen> createState() => _TvRailsHomeScreenState();
}

class _TvRailsHomeScreenState extends State<TvRailsHomeScreen> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<List<String>>? _recentSub;

  /// Chaîne du HÉRO (aperçu vidéo) : dernière regardée, sinon 1er favori,
  /// sinon 1re chaîne — le template promettait « Aperçu » depuis le début,
  /// le héro n'était qu'une icône statique. Même cascade que le Lanceur.
  Channel? _hero;

  /// Aperçu héro actif ? Coupé AVANT tout écran poussé (jamais 2 flux).
  bool _previewLive = true;

  /// Jeton anti-course (patron Lanceur) : deux événements playlist/zapping
  /// rapprochés lancent deux _recomputeHero — seule la passe la plus
  /// récente écrit (sinon une chaîne d'une source supprimée pouvait rester
  /// en héro, aperçu mort).
  int _heroGen = 0;

  // Map id→Channel MÉMOÏSÉE par identité de liste (patron Lanceur) :
  // reconstruire une map O(N) du bouquet entier (10-50 k chaînes) à chaque
  // événement coûtait 10-60 ms pour quelques lookups.
  List<Channel>? _byIdSource;
  Map<String, Channel>? _byIdCache;

  Map<String, Channel> _byId(List<Channel> all) {
    if (!identical(all, _byIdSource)) {
      _byIdSource = all;
      _byIdCache = <String, Channel>{for (final Channel c in all) c.id: c};
    }
    return _byIdCache!;
  }

  @override
  void initState() {
    super.initState();
    _recomputeHero();
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((_) => _recomputeHero());
    _recentSub = RecentlyWatchedRepository.instance.stream
        .listen((_) => _recomputeHero());
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  void _recomputeHero() {
    final int gen = ++_heroGen;
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    if (all.isEmpty) {
      if (mounted) setState(() => _hero = null);
      return;
    }
    final Map<String, Channel> byId = _byId(all);
    Channel? hero;
    for (final String id in RecentlyWatchedRepository.instance.current) {
      hero = byId[id];
      if (hero != null) break;
    }
    if (hero == null) {
      for (final String id in FavoritesRepository.instance.current) {
        hero = byId[id];
        if (hero != null) break;
      }
    }
    hero ??= all.first;
    if (gen != _heroGen || !mounted) return;
    if (_hero?.id != hero.id) setState(() => _hero = hero);
  }

  /// RETOUR INTELLIGENT (parité Lanceur) : contrôle de l'accueil (tuile de
  /// navigation, icône du haut, héro) à RE-FOCUSER au retour d'un écran
  /// poussé (BACK). Sans ça, le focus repartait sur l'élément d'autofocus
  /// initial au lieu de l'endroit exact qu'on avait quitté.
  String? _restoreFocusId;

  void _clearRestore() {
    if (_restoreFocusId != null) setState(() => _restoreFocusId = null);
  }

  /// Suspend l'aperçu héro sur une frame PROPRE (même garde que le Lanceur :
  /// la SurfaceView en hybrid composition laisse sinon sa dernière trame
  /// « percer » par-dessus l'écran poussé — et 2 flux resteraient ouverts).
  Future<void> _suspendPreview() async {
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
  }

  void _resumePreview() {
    if (mounted) setState(() => _previewLive = true);
  }

  Future<void> _open(Widget screen, {String? restoreId}) async {
    // On ENVELOPPE l'écran poussé dans un Material (transparent) : sans ancêtre
    // Material, Flutter dessine des DOUBLES SOULIGNEMENTS JAUNES sous chaque
    // texte (signal « pas de Material »). Les écrans « bucket » (Réglages,
    // Recherche, Séries, Films…) ne s'enveloppent pas eux-mêmes → on le fait ici
    // (comme le fait déjà le Lanceur). Résultat : typographie NETTE, pas de
    // lignes jaunes.
    await _suspendPreview();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            Material(type: MaterialType.transparency, child: screen)));
    if (!mounted) return;
    // RETOUR (BACK) : l'aperçu se ré-arme et le contrôle quitté reprend le
    // focus (retour intelligent — jamais « en haut de l'accueil »).
    setState(() {
      _previewLive = true;
      if (restoreId != null) _restoreFocusId = restoreId;
    });
  }

  Future<void> _confirmExit(BuildContext c) async {
    // Dialogue de sortie PREMIUM partagé (le même que le template classique
    // — l'AlertDialog nu faisait « téléphone », pas « salon »).
    final String? action = await showExitDialog(c);
    if (!c.mounted) return;
    if (action == 'restart') {
      RestartWidget.restart(c);
    } else if (action == 'quit') {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        _confirmExit(context);
      },
      // ÉCRAN DE VEILLE anti burn-in (parité accueil Classique) : sans lui,
      // une box laissée sur ce template marquait la dalle OLED. Le watcher
      // ne s'arme que quand l'accueil est la route visible (garde interne).
      child: TvScreensaverWatcher(
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
                          // RELOAD réel : ce bouton ⟳ ouvrait « En direct »
                          // (doublon du héro et de la tuile Direct) — rien ne
                          // se rechargeait. On déclenche le rechargement
                          // logiciel (même action que « Redémarrer » de la
                          // boîte Quitter), conforme au rôle du bouton.
                          onSelect: () => RestartWidget.restart(context)),
                      const SizedBox(width: 10),
                      _TopIcon(
                          icon: Icons.person_outline_rounded,
                          restoreId: 'profil',
                          restoreFocusId: _restoreFocusId,
                          onRestored: _clearRestore,
                          onSelect: () => _open(const TvProfilesScreen(),
                              restoreId: 'profil')),
                      const SizedBox(width: 10),
                      _TopIcon(
                          icon: Icons.settings_outlined,
                          restoreId: 'reglages',
                          restoreFocusId: _restoreFocusId,
                          onRestored: _clearRestore,
                          onSelect: () => _open(const TvSettingsScreen(),
                              restoreId: 'reglages')),
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
                            // L'autofocus d'entrée se désarme quand une
                            // restauration est due (retour intelligent).
                            autofocus: _restoreFocusId == null,
                            channel: _hero,
                            previewEnabled: _previewLive,
                            restoreFocus: _restoreFocusId == 'hero',
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvLiveScreen(),
                                restoreId: 'hero'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 32,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(context.l10n.tvQuickAccess,
                                  style: TvTokens.ui(TvDimens.label,
                                      weight: FontWeight.w600, color: _rTitle)),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _NavTile(
                                  icon: Icons.star_rounded,
                                  label: context.l10n.navFavorites,
                                  restoreId: 'favoris',
                                  restoreFocusId: _restoreFocusId,
                                  onRestored: _clearRestore,
                                  onSelect: () => _open(const TvLiveScreen(),
                                      restoreId: 'favoris'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _NavTile(
                                  icon: Icons.grid_view_rounded,
                                  label: context.l10n.tvNavGuide,
                                  restoreId: 'guide',
                                  restoreFocusId: _restoreFocusId,
                                  onRestored: _clearRestore,
                                  onSelect: () => _open(
                                      const TvGuideGridScreen(),
                                      restoreId: 'guide'),
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
                            label: context.l10n.tvNavLive,
                            restoreId: 'direct',
                            restoreFocusId: _restoreFocusId,
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvLiveScreen(),
                                restoreId: 'direct'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.movie_rounded,
                            label: context.l10n.tvNavFilms,
                            restoreId: 'films',
                            restoreFocusId: _restoreFocusId,
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvFilmsScreen(),
                                restoreId: 'films'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.video_library_rounded,
                            label: context.l10n.tvNavSeries,
                            restoreId: 'series',
                            restoreFocusId: _restoreFocusId,
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvSeriesScreen(),
                                restoreId: 'series'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.replay_rounded,
                            label: context.l10n.detailCatchup,
                            restoreId: 'catchup',
                            restoreFocusId: _restoreFocusId,
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvRecordingsScreen(),
                                restoreId: 'catchup'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _NavTile(
                            icon: Icons.search_rounded,
                            label: context.l10n.tvNavSearch,
                            restoreId: 'recherche',
                            restoreFocusId: _restoreFocusId,
                            onRestored: _clearRestore,
                            onSelect: () => _open(const TvSearchScreen(),
                                restoreId: 'recherche'),
                          ),
                        ),
                        // Choix des modèles A/B/C/D : réservé au mode
                        // Développeur (décision du 21/08).
                        if (TvDeveloperMode.instance.enabled) ...<Widget>[
                          const SizedBox(width: 14),
                          Expanded(
                            child: _NavTile(
                              icon: Icons.dashboard_customize_rounded,
                              label: context.l10n.tvNavTemplates,
                              restoreId: 'templates',
                              restoreFocusId: _restoreFocusId,
                              onRestored: _clearRestore,
                              onSelect: () => _open(
                                  const TvHomeTemplateScreen(),
                                  restoreId: 'templates'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ---- Rail FAVORIS EN DIRECT (vraie donnée) ----
                  // Le TITRE vit désormais DANS le rail : sans favoris, le
                  // bloc ENTIER se replie (avant, « Favoris en direct »
                  // restait affiché au-dessus d'une zone vide). Le rail
                  // suspend l'aperçu héro AVANT d'ouvrir le lecteur (jamais
                  // 2 flux) et le ré-arme au retour.
                  _LiveFavoritesRail(
                      onPlaySuspend: _suspendPreview,
                      onResume: _resumePreview),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Icône de la barre haute (reload / profil / réglages).
/// FocusNode PROPRE : au retour d'un écran ouvert depuis cette icône
/// (BACK), elle REPREND le focus (retour intelligent, patron Lanceur).
class _TopIcon extends StatefulWidget {
  const _TopIcon(
      {required this.icon,
      required this.onSelect,
      this.restoreId,
      this.restoreFocusId,
      this.onRestored});
  final IconData icon;
  final VoidCallback onSelect;

  /// Identité STABLE de cette icône (ex. 'profil') pour la restauration.
  final String? restoreId;

  /// Contrôle désigné par l'accueil pour reprendre le focus au retour.
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_TopIcon> createState() => _TopIconState();
}

class _TopIconState extends State<_TopIcon> {
  final FocusNode _node = FocusNode(debugLabel: 'rails-top-icon');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.restoreId != null &&
        widget.restoreFocusId != null &&
        widget.restoreFocusId == widget.restoreId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.restoreId) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return TvFocusBuilder(
      focusNode: _node,
      scale: TvFocusScale.small,
      onSelect: widget.onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: pressed
                ? _rPressA
                : (focused ? _rFocusA : Colors.transparent),
            shape: BoxShape.circle,
            border: (focused || pressed)
                ? Border.all(
                    color: pressed ? _rNeonPress : _rBorderFocus, width: 2)
                : null,
            boxShadow: (focused || pressed)
                ? <BoxShadow>[
                    BoxShadow(
                      color: (pressed ? _rNeonPress : _rNeon)
                          .withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Icon(widget.icon,
              size: 28, color: focused ? _rText : _rMuted),
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

/// Héro : APERÇU VIDÉO EN DIRECT de la dernière chaîne regardée + badge
/// « Direct ». La description du template promettait « Aperçu » — le héro
/// n'était qu'une icône statique. L'aperçu réutilise TOUTE la mécanique
/// éprouvée de TvLivePreview (muet, anti-rebond, repli logo, moteur natif).
/// PETITE BOX (profil léger) : pas de vidéo permanente — logo de la chaîne.
class _Hero extends StatefulWidget {
  const _Hero({
    required this.onSelect,
    this.autofocus = false,
    this.channel,
    this.previewEnabled = true,
    this.restoreFocus = false,
    this.onRestored,
  });
  final VoidCallback onSelect;
  final bool autofocus;

  /// Chaîne prévisualisée (dernière regardée / 1er favori / 1re chaîne) —
  /// null tant que la playlist n'est pas ingérée (icône de repli).
  final Channel? channel;

  /// `false` = aperçu suspendu (un écran va être poussé — jamais 2 flux).
  final bool previewEnabled;

  /// `true` = l'accueil désigne le héro pour reprendre le focus au retour
  /// (BACK) de l'écran qu'il avait ouvert (retour intelligent).
  final bool restoreFocus;
  final VoidCallback? onRestored;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final FocusNode _node = FocusNode(debugLabel: 'rails-hero');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.restoreFocus) return;
        _node.requestFocus();
        widget.onRestored?.call();
      });
    }
    final Channel? ch = widget.channel;
    return TvFocusBuilder(
      focusNode: _node,
      autofocus: widget.autofocus,
      scale: TvFocusScale.medium,
      onSelect: widget.onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return _railsShell(
          focused: focused,
          pressed: pressed,
          radius: 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (ch != null && !TvMemoryGuard.instance.lowSpec)
                  TvLivePreview(channel: ch, enabled: widget.previewEnabled)
                else if (ch != null)
                  Center(
                      child: TvChannelLogo(
                          logoUrl: ch.logoUrl,
                          label: ch.name,
                          size: 96,
                          radius: 14))
                else
                  Center(
                    child: Icon(Icons.live_tv_rounded,
                        size: 92, color: focused ? _rText : _rMuted),
                  ),
                // Bandeau bas : badge Play + nom de la chaîne, sur un voile
                // violet — lisible par-dessus la vidéo, fidèle au thème.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Colors.transparent, Color(0xCC1B0024)],
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
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
                              Text(context.l10n.tvNavLive,
                                  style: TvTokens.ui(TvDimens.body,
                                      weight: FontWeight.w700, color: _rText)),
                            ],
                          ),
                        ),
                        if (ch != null) ...<Widget>[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(ch.cleanName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TvTokens.ui(TvDimens.title,
                                    weight: FontWeight.w700, color: _rText)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tuile de navigation (icône + label), style IBO rails.
/// FocusNode PROPRE (patron _NavTile du Lanceur) : au retour de l'écran
/// ouvert par cette tuile (BACK), elle REPREND le focus — retour
/// intelligent, jamais « en haut de l'accueil ».
class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.restoreId,
    this.restoreFocusId,
    this.onRestored,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  /// Identité STABLE de cette tuile (ex. 'films') pour la restauration.
  final String? restoreId;

  /// Tuile désignée par l'accueil pour reprendre le focus au retour.
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  final FocusNode _node = FocusNode(debugLabel: 'rails-nav-tile');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.restoreId != null &&
        widget.restoreFocusId != null &&
        widget.restoreFocusId == widget.restoreId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.restoreId) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return TvFocusBuilder(
      focusNode: _node,
      scale: TvFocusScale.small,
      onSelect: widget.onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return _railsShell(
          focused: focused,
          pressed: pressed,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon,
                  size: 38, color: focused ? _rText : _rMuted),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(widget.label.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(13,
                        weight: FontWeight.w700,
                        color: focused ? _rText : _rMuted,
                        spacing: 1.6)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Un favori + son programme en cours (calculé au moment de l'affichage).
class _FavSlot {
  const _FavSlot({required this.channel, this.program});
  final Channel channel;
  final EpgProgram? program;
}

/// Rail « Favoris en direct » — 100 % TV natif.
///
/// Lit les favoris (FavoritesRepository) et, pour chacun, le programme en
/// cours (EpgRepository). Au tap, ouvre TvPlayerScreen (ExoPlayer/Media3)
/// avec la liste des favoris → zapping haut/bas dans le lecteur, sans
/// jamais toucher au lecteur mobile (media_kit). Si aucun favori, le rail
/// se replie (SizedBox.shrink) — l'accueil reste propre.
class _LiveFavoritesRail extends StatefulWidget {
  const _LiveFavoritesRail({this.onPlaySuspend, this.onResume});

  /// Suspend l'aperçu héro de l'accueil sur une frame propre AVANT d'ouvrir
  /// le lecteur (jamais 2 flux) ; [onResume] le ré-arme au retour (BACK).
  final Future<void> Function()? onPlaySuspend;
  final VoidCallback? onResume;

  @override
  State<_LiveFavoritesRail> createState() => _LiveFavoritesRailState();
}

class _LiveFavoritesRailState extends State<_LiveFavoritesRail> {
  List<_FavSlot> _slots = <_FavSlot>[];
  bool _loading = true;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<void>? _epgSub;

  /// Tic lent : le programme EN COURS et sa barre de progression sont
  /// figés au moment du calcul — sans tic, une émission finie restait
  /// affichée toute la soirée (patron MiniEpgNowNext, en plus espacé).
  Timer? _ticker;

  // Défilement propre au rail : sert à REVENIR sur la chaîne quittée au retour
  // du lecteur (si sa carte a défilé hors écran).
  final ScrollController _scroll = ScrollController();
  // Chaîne à re-focaliser au RETOUR du lecteur (par id, pas par index : la liste
  // peut avoir changé d'ordre/longueur pendant la lecture). Sans ça, le focus
  // retombait sur la 1re carte → « ça repart en haut de l'accueil ».
  String? _restoreId;
  // Largeur d'une carte (260) + séparateur (14) = pas horizontal d'un cran.
  static const double _kCardStride = 260 + 14;

  @override
  void initState() {
    super.initState();
    _favSub =
        FavoritesRepository.instance.favoritesStream.listen((Set<String> _) {
      _recompute();
    });
    // Le rail dépend AUSSI de la PLAYLIST (requête SQL sur `channels`) : au
    // boot il se calcule souvent AVANT la fin de l'ingestion (0 ligne en
    // base → rail vide) et un changement de source n'émettait rien ici →
    // favoris invisibles/périmés jusqu'au redémarrage. Même double écoute
    // (favoris + chaînes) que l'écran « En direct » (tv_live_screen).
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((List<Channel> _) => _recompute());
    // L'EPG s'importe APRÈS le 1er rendu (téléchargement XMLTV) : sans
    // cette écoute, toutes les cartes restaient sur « En direct » sans
    // programme jusqu'au prochain toggle ★ (patron tv_guide_screen).
    _epgSub = EpgRepository.instance.changes.listen((_) => _recompute());
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_slots.isNotEmpty) _recompute();
    });
    _recompute();
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _chanSub?.cancel();
    _epgSub?.cancel();
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Jeton anti-course (revue de code) : _recompute est async depuis le
  /// passage aux requêtes SQL — deux événements favoris rapprochés = deux
  /// requêtes concurrentes, la plus LENTE pouvait écraser la plus récente.
  int _recomputeGen = 0;

  Future<void> _recompute() async {
    final int gen = ++_recomputeGen;
    final Set<String> favIds = FavoritesRepository.instance.current;
    if (favIds.isEmpty) {
      if (mounted) {
        setState(() {
          _slots = <_FavSlot>[];
          _loading = false;
        });
      }
      return;
    }

    // Requêtes SQL ponctuelles (patron tv_live_screen) au lieu d'une Map
    // id→Channel de TOUT le bouquet reconstruite à chaque toggle ★ (O(N)
    // sur 10-50 k chaînes pour n'en garder que 12). L'ordre des favoris
    // (insertion) est préservé en réordonnant le résultat.
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in await PlaylistRepository.instance
          .getChannelsByExternalIds(favIds.toList(growable: false)))
        c.id: c,
    };
    final List<Channel> favorites = <Channel>[];
    for (final String id in favIds) {
      final Channel? c = byId[id];
      if (c != null) favorites.add(c);
    }
    // On limite à 12 favoris — au-delà c'est trop de requêtes EPG et le
    // rail scrolle de toute façon.
    final List<Channel> picked = favorites.take(12).toList();

    // EPG en PARALLÈLE (Future.wait) : la boucle `await` séquentielle
    // additionnait 12 allers-retours SQLite avant d'afficher le rail.
    final List<EpgProgram?> programs = await Future.wait(
      picked.map((Channel c) async {
        try {
          return await EpgRepository.instance.currentProgram(c.id);
        } catch (_) {
          return null;
        }
      }),
    );
    final List<_FavSlot> slots = <_FavSlot>[
      for (int i = 0; i < picked.length; i++)
        _FavSlot(channel: picked[i], program: programs[i]),
    ];
    if (mounted && gen == _recomputeGen) {
      setState(() {
        _slots = slots;
        _loading = false;
      });
    }
  }

  Future<void> _play(int index) async {
    final List<Channel> list =
        _slots.map((_FavSlot s) => s.channel).toList(growable: false);
    if (list.isEmpty || index < 0 || index >= list.length) return;
    final String playedId = list[index].id; // on retiendra CETTE chaîne
    // L'aperçu héro est LIBÉRÉ d'abord (l'accueil reste monté sous la
    // route poussée — sans ça, 2 flux resteraient ouverts).
    await widget.onPlaySuspend?.call();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
    widget.onResume?.call();
    // RETOUR INTELLIGENT : on re-focuse la chaîne RÉELLEMENT regardée en
    // dernier (le zapping haut/bas du lecteur a pu changer de chaîne —
    // l'historique est alimenté à chaque zap), sinon la chaîne ouverte.
    if (!mounted) return;
    String? target;
    for (final String id in RecentlyWatchedRepository.instance.current) {
      if (_slots.any((_FavSlot s) => s.channel.id == id)) {
        target = id;
        break;
      }
    }
    // Si la chaîne a été RETIRÉE des favoris PENDANT la lecture (★ dans le
    // lecteur), sa carte n'existe plus : sans repli, AUCUN node ne reprenait
    // le focus → télécommande muette au retour. On retombe sur la 1re carte.
    target ??= _slots.any((_FavSlot s) => s.channel.id == playedId)
        ? playedId
        : (_slots.isEmpty ? null : _slots.first.channel.id);
    if (target == null) return; // plus aucun favori → rail replié
    setState(() => _restoreId = target);
    _scrollToId(target);
  }

  /// Amène la carte de [id] dans la vue (si besoin) pour qu'elle se construise
  /// et puisse reprendre le focus au retour du lecteur.
  void _scrollToId(String id) {
    final int idx = _slots.indexWhere((_FavSlot s) => s.channel.id == id);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double target =
          (idx * _kCardStride).clamp(0.0, _scroll.position.maxScrollExtent);
      final double left = _scroll.offset;
      final double right = left + _scroll.position.viewportDimension;
      final double cardLeft = idx * _kCardStride;
      if (cardLeft < left || cardLeft + 260 > right) {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_slots.isEmpty) return const SizedBox.shrink();
    // Titre + liste dans le MÊME widget : sans favoris, tout se replie
    // ensemble (le titre seul au-dessus du vide faisait « cassé »).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(context.l10n.tvFavoritesLive,
            style: TvTokens.ui(TvDimens.title,
                weight: FontWeight.w600, color: _rTitle)),
        const SizedBox(height: 8),
        SizedBox(
          height: 168,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemCount: _slots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (BuildContext context, int i) {
              final _FavSlot slot = _slots[i];
              // Clé STABLE (par id) : le focus SUIT la carte même si la liste
              // change d'ordre pendant la lecture → la restauration du focus
              // fonctionne.
              return _FavCard(
                key: ValueKey<String>(slot.channel.id),
                slot: slot,
                // PAS d'autofocus initial : le héro est LE point d'entrée
                // de l'accueil. L'ancien autofocus de la 1re carte partait
                // en COURSE avec celui du héro (le rail se construit après
                // le chargement SQL → il volait le focus par surprise).
                autofocus: false,
                restoreFocus: slot.channel.id == _restoreId,
                onRestored: () => _restoreId = null,
                onSelect: () => _play(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Carte d'un favori : logo + nom chaîne + programme en cours + barre de
/// progression. Style IBO rails (tuile #411C4C, focus #391A43 + liseré clair).
class _FavCard extends StatefulWidget {
  const _FavCard({
    super.key,
    required this.slot,
    required this.autofocus,
    required this.onSelect,
    this.restoreFocus = false,
    this.onRestored,
  });
  final _FavSlot slot;
  final bool autofocus;
  final VoidCallback onSelect;

  /// `true` quand l'écran DÉSIGNE cette carte pour reprendre le focus au retour
  /// du lecteur (la chaîne qu'on regardait). Elle (re)prend alors le focus.
  final bool restoreFocus;

  /// Appelé une fois le focus repris → l'écran libère le drapeau.
  final VoidCallback? onRestored;

  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  // Node possédé par la carte : on en a besoin pour RE-DEMANDER le focus au
  // retour du lecteur (passé à TvFocusBuilder qui ne le dispose alors pas).
  final FocusNode _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  double? _progress() {
    final EpgProgram? p = widget.slot.program;
    if (p == null) return null;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int total = p.stopTime - p.startTime;
    if (total <= 0) return null;
    final double frac = (now - p.startTime) / total;
    if (frac.isNaN) return null;
    return frac.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // RESTAURATION DU FOCUS au retour du lecteur : quand l'écran nous désigne,
    // on (re)prend le focus en post-frame puis on libère le drapeau.
    if (widget.restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.restoreFocus) return;
        _node.requestFocus();
        widget.onRestored?.call();
      });
    }
    return TvFocusBuilder(
      focusNode: _node,
      autofocus: widget.autofocus,
      scale: TvFocusScale.small,
      onSelect: widget.onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return _railsShell(
          focused: focused,
          pressed: pressed,
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(12),
            child: _favCardBody(focused),
          ),
        );
      },
    );
  }

  Widget _favCardBody(bool focused) {
    final Channel ch = widget.slot.channel;
    final EpgProgram? prog = widget.slot.program;
    final double? progress = _progress();
    return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: ch.hasLogo
                        ? CachedNetworkImage(
                            imageUrl: ch.logoUrl!,
                            fit: BoxFit.contain,
                            // Décodage borné (48 px affichés) — anti-OOM.
                            memCacheWidth: 128,
                            memCacheHeight: 128,
                            // Placeholder = même icône que l'erreur (taille
                            // fixe → zéro saut) + fade court. Revue V1.
                            fadeInDuration:
                                const Duration(milliseconds: 150),
                            placeholder: (_, __) => const Icon(
                                Icons.live_tv_rounded,
                                size: 24,
                                color: _rMuted),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.live_tv_rounded,
                                size: 24,
                                color: _rMuted),
                          )
                        : const Icon(Icons.live_tv_rounded,
                            size: 24, color: _rMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.label,
                          weight: FontWeight.w700,
                          color: focused ? _rText : _rTitle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  prog?.title ?? context.l10n.homeLiveNow,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.body,
                      color: focused ? _rText : _rMuted),
                ),
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_rPlay),
                  ),
                ),
              ],
            ],
          );
  }
}
