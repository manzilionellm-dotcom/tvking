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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_tokens.dart';
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
  Alignment _pos = Alignment.center;
  String _time = '';

  @override
  void initState() {
    super.initState();
    _tickClock();
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

  void _tickClock() {
    final DateTime now = DateTime.now();
    final String h = now.hour.toString().padLeft(2, '0');
    final String m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _time = '$h:$m');
  }

  @override
  void dispose() {
    _move?.cancel();
    _clock?.cancel();
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
        if (event is KeyDownEvent) _wake();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _wake,
        child: Container(
          color: Colors.black, // noir PUR : pixels OLED éteints = zéro usure
          child: Stack(
            children: <Widget>[
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
                child: Text(
                  _time,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.mutedDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
