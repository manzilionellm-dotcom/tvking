// =========================================================
//  tv_screensaver.dart — Écran de veille anti-burn-in (TV)
// =========================================================
//  Après 10 min SANS toucher la télécommande sur l'ACCUEIL, un écran de
//  veille s'affiche : fond noir + logo qui CHANGE DE PLACE lentement
//  (un logo statique « marquerait » les dalles OLED — le mouvement
//  l'empêche) + l'heure. N'importe quelle touche le referme.
//
//  RÈGLE DE STABILITÉ (la plus importante) : le veilleur ne se déclenche
//  QUE si l'accueil est l'écran VISIBLE (route au sommet). Dès qu'un écran
//  est poussé PAR-DESSUS — lecteur vidéo, réglages, recherche… — il ne
//  s'arme JAMAIS. Il est donc IMPOSSIBLE qu'il interrompe une lecture :
//  zéro contact avec le lecteur, zéro risque pour l'image.
// =========================================================
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import 'tv_components.dart';

/// Enveloppe l'ACCUEIL : surveille l'inactivité (touches + toucher) et pousse
/// l'écran de veille quand l'accueil est resté visible 10 min sans action.
class TvScreensaverWatcher extends StatefulWidget {
  const TvScreensaverWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<TvScreensaverWatcher> createState() => _TvScreensaverWatcherState();
}

class _TvScreensaverWatcherState extends State<TvScreensaverWatcher> {
  static const Duration _idleDelay = Duration(minutes: 10);

  Timer? _idle;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // Écoute GLOBALE des touches (télécommande/clavier) : chaque appui
    // remet le compteur d'inactivité à zéro. On renvoie `false` pour ne
    // JAMAIS consommer la touche (la navigation continue normalement).
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _arm();
    return false; // on n'intercepte rien, on observe seulement
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(_idleDelay, _maybeShow);
  }

  void _maybeShow() {
    if (!mounted || _showing) {
      _arm();
      return;
    }
    // GARDE-FOU : uniquement si l'accueil est la route AU SOMMET. Lecteur,
    // réglages, recherche… au-dessus → on ne fait RIEN (on re-armera).
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      _arm();
      return;
    }
    _showing = true;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => const _TvScreensaverScreen(),
        ))
        .then((_) {
      _showing = false;
      _arm();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le toucher (TV tactiles / souris) réarme aussi le compteur.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _arm(),
      child: widget.child,
    );
  }
}

/// L'écran de veille lui-même : noir profond, logo qui se déplace toutes les
/// 20 s (anti burn-in), heure discrète. N'importe quelle touche → retour.
class _TvScreensaverScreen extends StatefulWidget {
  const _TvScreensaverScreen();

  @override
  State<_TvScreensaverScreen> createState() => _TvScreensaverScreenState();
}

class _TvScreensaverScreenState extends State<_TvScreensaverScreen> {
  final Random _rng = Random();
  Timer? _move;
  Timer? _clock;
  Timer? _art;
  Alignment _pos = Alignment.center;
  String _time = '';

  /// « ART MODE » : affiches du catalogue en galerie plein écran (fond
  /// flouté + affiche nette + léger zoom Ken Burns). Vide → on retombe sur
  /// le logo tamisé classique (aucun VOD chargé, flavor sans cinéma…).
  List<VodMovie> _gallery = const <VodMovie>[];
  int _artIdx = 0;

  @override
  void initState() {
    super.initState();
    _tickClock();
    _initGallery();
    // Déplacement lent du logo : nouvelle position aléatoire toutes les 20 s
    // (borne 0.7 → jamais collé aux bords). AnimatedAlign fait le glissement.
    _move = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {
        _pos = Alignment(
          (_rng.nextDouble() * 2 - 1) * 0.7,
          (_rng.nextDouble() * 2 - 1) * 0.7,
        );
      });
    });
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _tickClock());
  }

  /// Prépare la galerie depuis le catalogue DÉJÀ en mémoire (zéro réseau) :
  /// affiches présentes, mélangées, plafonnées. Lance la rotation (12 s).
  void _initGallery() {
    final List<VodMovie> withArt = <VodMovie>[
      for (final VodMovie m in VodRepository.instance.cachedMovies)
        if ((m.posterUrl ?? '').isNotEmpty) m,
    ]..shuffle(_rng);
    if (withArt.isEmpty) return;
    _gallery = withArt.take(40).toList(growable: false);
    _art = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || _gallery.isEmpty) return;
      setState(() => _artIdx = (_artIdx + 1) % _gallery.length);
    });
  }

  void _tickClock() {
    final DateTime now = DateTime.now();
    final String h = now.hour.toString().padLeft(2, '0');
    final String m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _time = '$h:$m');
  }

  /// Ligne météo « 21° · Paris » (si la météo est déjà en cache — on ne
  /// déclenche AUCUN appel réseau depuis le veilleur, on lit seulement).
  String get _weatherLabel {
    final Greeting? g = GreetingRepository.instance.current;
    if (g == null) return '';
    final String t =
        g.tempC == null ? '' : '${g.tempC!.round()}°';
    final List<String> parts = <String>[
      if (g.emoji.isNotEmpty || t.isNotEmpty) '${g.emoji} $t'.trim(),
      if (g.city.isNotEmpty) g.city,
    ];
    return parts.join(' · ');
  }

  @override
  void dispose() {
    _move?.cancel();
    _clock?.cancel();
    _art?.cancel();
    super.dispose();
  }

  void _wake() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      // N'importe quelle touche (flèches, OK, Retour…) réveille.
      onKeyEvent: (FocusNode node, KeyEvent event) {
        final LogicalKeyboardKey k = event.logicalKey;
        // Volume / mute / power : on laisse PASSER au système — les
        // consommer donnait l'impression d'une box gelée (audit D17).
        if (k == LogicalKeyboardKey.audioVolumeUp ||
            k == LogicalKeyboardKey.audioVolumeDown ||
            k == LogicalKeyboardKey.audioVolumeMute ||
            k == LogicalKeyboardKey.tvPower) {
          return KeyEventResult.ignored;
        }
        // Réveil au RELÂCHEMENT : se réveiller au key-DOWN laissait le
        // key-UP orphelin activer la tuile focus de l'écran dessous
        // (audit D1/D17). Le down est consommé sans effet.
        if (event is KeyUpEvent) _wake();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _wake,
        child: Container(
          color: Colors.black, // noir PUR : pixels OLED éteints = zéro usure
          child: Stack(
            children: <Widget>[
              // ART MODE : galerie d'affiches si le catalogue est chargé,
              // sinon logo tamisé qui se déplace (comportement d'origine).
              if (_gallery.isNotEmpty)
                _ArtSlide(
                  key: ValueKey<String>(_gallery[_artIdx].id),
                  movie: _gallery[_artIdx],
                )
              else
                AnimatedAlign(
                  alignment: _pos,
                  duration: const Duration(seconds: 4),
                  curve: Curves.easeInOut,
                  child: Opacity(
                    opacity: 0.55, // logo tamisé (doux la nuit, anti-marquage)
                    child: const TvLogo(width: 200),
                  ),
                ),
              Positioned(
                right: 40,
                bottom: 32,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      _time,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: TvTokens.mutedDim,
                      ),
                    ),
                    if (_weatherLabel.isNotEmpty)
                      Text(
                        _weatherLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: TvTokens.mutedDim,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une « diapo » Art Mode : fond plein écran flouté + assombri (la même
/// affiche, pour une ambiance colorée) et l'affiche NETTE centrée, avec un
/// lent zoom Ken Burns. Fondu d'entrée (le Stack parent croise les diapos
/// via la ValueKey). Best-effort : image absente → rien (le noir reste).
class _ArtSlide extends StatefulWidget {
  const _ArtSlide({required this.movie, super.key});
  final VodMovie movie;

  @override
  State<_ArtSlide> createState() => _ArtSlideState();
}

class _ArtSlideState extends State<_ArtSlide> {
  double _opacity = 0.0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    // Fondu + zoom Ken Burns amorcés à la première frame (transition douce).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {
        _opacity = 1.0;
        _scale = 1.08;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final String url = widget.movie.posterUrl ?? '';
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOut,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Fond : affiche plein cadre, floutée + assombrie (ambiance).
          if (url.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 200, // flouté → une petite déco suffit
                placeholder: (_, __) => const ColoredBox(color: Colors.black),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Colors.black),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xC008080A), Color(0xE608080A)],
              ),
            ),
          ),
          // Affiche NETTE centrée, avec lent zoom (Ken Burns).
          Center(
            child: AnimatedScale(
              scale: _scale,
              duration: const Duration(seconds: 12),
              curve: Curves.easeOut,
              child: FractionallySizedBox(
                heightFactor: 0.72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    memCacheWidth: 500,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
