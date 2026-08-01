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

import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_memory_guard.dart';
import '../core/tv_tokens.dart';
import '../data/channel_reliability.dart';
import '../data/hero_picker.dart';
import 'tv_live_preview.dart';
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_screen.dart';
import 'tv_player_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_recordings_screen.dart';
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
      // Halo RÉDUIT (audit fluidité #12) : cette ombre s'empilait sur les
      // DEUX ombres de focus de TvFocusable (blur 34-40 px) → trois grands
      // flous ré-rasterisés à chaque frame de la transition de focus, le
      // « collant » typique des Mali-G31. Le glow TvFocusable porte déjà
      // le signal ; ici on ne garde qu'un liseré doux bon marché.
      boxShadow: (focused || pressed)
          ? <BoxShadow>[
              BoxShadow(
                color: halo.withValues(alpha: pressed ? 0.45 : 0.30),
                blurRadius: 8,
              ),
            ]
          : null,
    ),
    child: child,
  );
}

class TvRailsHomeScreen extends StatelessWidget {
  const TvRailsHomeScreen({super.key});

  void _open(BuildContext c, Widget screen) {
    // On ENVELOPPE l'écran poussé dans un Material (transparent) : sans ancêtre
    // Material, Flutter dessine des DOUBLES SOULIGNEMENTS JAUNES sous chaque
    // texte (signal « pas de Material »). Les écrans « bucket » (Réglages,
    // Recherche, Séries, Films…) ne s'enveloppent pas eux-mêmes → on le fait ici
    // (comme le fait déjà le Lanceur). Résultat : typographie NETTE, pas de
    // lignes jaunes.
    Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) =>
            Material(type: MaterialType.transparency, child: screen)));
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
            // Focus initial (audit D5) : sans lui le 1er OK est avalé.
            autofocus: true,
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
                  const SizedBox(height: 168, child: _LiveFavoritesRail()),
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
class _Hero extends StatefulWidget {
  const _Hero({required this.onSelect, this.autofocus = false});
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<_Hero> createState() => _HeroState();
}

/// Héro VIVANT (parité Modèle B) : au lieu d'une icône statique, le cadre
/// montre l'aperçu EN DIRECT d'une chaîne aimée — candidats ordonnés par la
/// brique pure hero_picker (récents → favoris → 1re chaîne, fiables d'abord
/// via le score n°38). Chaîne injouable → bascule auto sur la suivante
/// (TvLivePreview.onUnavailable) : jamais un grand cadre mort à l'accueil.
/// Indépendance : état 100 % local à CE template ; petite box → logo seul.
class _HeroState extends State<_Hero> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<List<String>>? _recentSub;
  List<Channel> _candidates = const <Channel>[];
  int _index = 0;

  Channel? get _hero =>
      _index < _candidates.length ? _candidates[_index] : null;

  @override
  void initState() {
    super.initState();
    _recompute();
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((_) => _recompute());
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((_) => _recompute());
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  // Map id→Channel mémoïsée par identité de liste (parité Modèle B) : le
  // bouquet fait 10-50 k chaînes — on ne la reconstruit pas à chaque
  // événement de playlist/zapping.
  List<Channel>? _byIdSource;
  Map<String, Channel>? _byIdCache;

  Map<String, Channel> _byId(List<Channel> all) {
    if (!identical(all, _byIdSource)) {
      _byIdSource = all;
      _byIdCache = <String, Channel>{for (final Channel c in all) c.id: c};
    }
    return _byIdCache!;
  }

  void _recompute() {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    if (all.isEmpty) {
      if (mounted && _candidates.isNotEmpty) {
        setState(() {
          _candidates = const <Channel>[];
          _index = 0;
        });
      }
      return;
    }
    final List<Channel> candidates = heroCandidates(
      all: all,
      byId: _byId(all),
      recents: RecentlyWatchedRepository.instance.current,
      favorites: FavoritesRepository.instance.current,
      isFlaky: ChannelReliability.instance.isFlaky,
    );
    if (mounted &&
        (candidates.isEmpty ||
            _candidates.isEmpty ||
            candidates.first.id != _candidates.first.id)) {
      setState(() {
        _candidates = candidates;
        _index = 0;
      });
    } else {
      _candidates = candidates;
    }
  }

  void _advance() {
    if (!mounted || _index + 1 >= _candidates.length) return;
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final Channel? hero = _hero;
    return TvFocusBuilder(
      autofocus: widget.autofocus,
      scale: TvFocusScale.medium,
      onSelect: widget.onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return _railsShell(
          focused: focused,
          pressed: pressed,
          radius: 16,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (hero == null)
                Center(
                  child: Icon(Icons.live_tv_rounded,
                      size: 92, color: focused ? _rText : _rMuted),
                )
              else if (TvMemoryGuard.instance.lowSpec)
                // Petite box : pas de vidéo permanente à l'accueil — le
                // logo suffit, le décodeur reste pour la lecture réelle.
                Center(
                    child: TvChannelLogo(
                        logoUrl: hero.logoUrl,
                        label: hero.name,
                        size: 96,
                        radius: 14))
              else
                TvLivePreview(
                  channel: hero,
                  onUnavailable: _advance,
                ),
              // Nom de la chaîne du héro, lisible par-dessus la vidéo.
              if (hero != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 74,
                  child: Text(hero.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.body,
                          weight: FontWeight.w800, color: _rText)),
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
      scale: TvFocusScale.small,
      onSelect: onSelect,
      pressedBuilder: (BuildContext context, bool focused, bool pressed) {
        return _railsShell(
          focused: focused,
          pressed: pressed,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 38, color: focused ? _rText : _rMuted),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(label.toUpperCase(),
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
  const _LiveFavoritesRail();

  @override
  State<_LiveFavoritesRail> createState() => _LiveFavoritesRailState();
}

class _LiveFavoritesRailState extends State<_LiveFavoritesRail> {
  List<_FavSlot> _slots = <_FavSlot>[];
  bool _loading = true;
  StreamSubscription<Set<String>>? _favSub;

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
    _recompute();
  }

  @override
  void dispose() {
    _favSub?.cancel();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
    // RETOUR du lecteur : on DÉSIGNE la chaîne quittée pour que SA carte
    // reprenne le focus (on revient où on était, pas en haut de l'accueil).
    if (!mounted) return;
    setState(() => _restoreId = playedId);
    _scrollToId(playedId);
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
    return ListView.separated(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      // Marge de construction élargie (audit D20) : avec les 250 px par
      // défaut, la carte suivante n'était parfois pas encore construite
      // → le D-pad refusait d'avancer sur box lente.
      cacheExtent: 600,
      itemCount: _slots.length,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (BuildContext context, int i) {
        final _FavSlot slot = _slots[i];
        // Clé STABLE (par id) : le focus SUIT la carte même si la liste change
        // d'ordre pendant la lecture → la restauration du focus fonctionne.
        return _FavCard(
          key: ValueKey<String>(slot.channel.id),
          slot: slot,
          // Autofocus initial sur la 1re carte SEULEMENT si on ne revient pas du
          // lecteur (sinon c'est la chaîne quittée qui doit reprendre le focus).
          autofocus: _restoreId == null && i == 0,
          restoreFocus: slot.channel.id == _restoreId,
          onRestored: () => _restoreId = null,
          onSelect: () => _play(i),
        );
      },
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
                  prog?.title ?? 'En direct',
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
