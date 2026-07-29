// =========================================================
//  player_gesture_layer.dart — Gestes tactiles du lecteur mobile
// =========================================================
//  Couche de gestes « standard lecteur vidéo » (MX Player / YouTube)
//  posée autour de la surface de lecture :
//
//    - Double-tap gauche / droite  → seek −10 s / +10 s (VOD/replay)
//    - Double-tap centre           → play / pause
//    - Glissé vertical DROITE     → volume du lecteur (0-100)
//    - Glissé vertical GAUCHE     → luminosité de l'écran
//    - Glissé horizontal           → scrub (seek relatif, VOD)
//
//  POURQUOI une couche séparée : video_player_screen.dart dépasse déjà
//  4000 lignes ; isoler ici l'état des gestes (drags en cours, timers
//  de feedback, cache de luminosité) garde l'écran lisible et la
//  logique gestuelle testable indépendamment du moteur.
//
//  ⚠️ ZAP TIKTOK : en live mobile, un PageView VERTICAL sert déjà à
//  zapper. Les glissés verticaux volume/luminosité ne sont alors PAS
//  posés (`verticalGesturesEnabled: false`) : un recognizer vertical
//  déclaré ici serait PLUS PROFOND que celui du PageView dans l'arène
//  de gestes Flutter et lui volerait le swipe → zap cassé. Un handler
//  `null` ne crée AUCUN recognizer : le swipe de zap reste intact.
//  Même logique pour le scrub : `seekEnabled` n'est vrai que pour du
//  contenu à durée RÉELLE (VOD / replay), jamais pour le live.
//
//  La couche ne connaît PAS media_kit : elle reçoit des callbacks
//  (position / durée / seek / volume) → zéro couplage moteur,
//  réutilisable telle quelle si le moteur change (cf. lecteur TV natif).
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Glissé vertical en cours (ou en train de s'estomper) : rien,
/// volume (moitié droite) ou luminosité (moitié gauche).
enum _VerticalDragMode { none, volume, brightness }

class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    required this.child,
    required this.onTap,
    required this.seekEnabled,
    required this.verticalGesturesEnabled,
    required this.position,
    required this.duration,
    required this.onSeekTo,
    required this.volume,
    required this.onSetVolume,
    required this.onDoubleTapCenter,
    super.key,
  });

  /// Surface de lecture (vidéo + overlays) sur laquelle poser les gestes.
  final Widget child;

  /// Tap simple → toggle de l'overlay des contrôles (comportement
  /// historique). NB : la présence d'un double-tap retarde le tap simple
  /// de ~300 ms (fenêtre de désambiguïsation Flutter) — c'est le même
  /// compromis que chez YouTube / MX Player.
  final VoidCallback onTap;

  /// `true` si le média a une durée RÉELLE (VOD / replay) : active le
  /// double-tap ±10 s et le scrub horizontal. Jamais vrai en live — la
  /// fenêtre de buffer libmpv y expose une pseudo-durée trompeuse.
  final bool seekEnabled;

  /// `false` quand le PageView de zap TikTok est actif (live mobile,
  /// cf. note d'en-tête) ou sur TV (pas de tactile) : les glissés
  /// verticaux volume/luminosité ne sont alors pas enregistrés.
  final bool verticalGesturesEnabled;

  /// Position courante de lecture (lue à la demande, jamais mise en cache).
  final Duration Function() position;

  /// Durée courante du média (0 si inconnue → gestes de seek inertes).
  final Duration Function() duration;

  /// Seek ABSOLU, déjà borné [0, durée] par la couche. Sans toast : le
  /// feedback visuel (flash ±10 s / aperçu de scrub) est géré ici.
  final void Function(Duration target) onSeekTo;

  /// Volume du lecteur, échelle media_kit : 0-100.
  final double Function() volume;
  final void Function(double volume) onSetVolume;

  /// Double-tap au CENTRE → play / pause (fonctionne aussi en live).
  final VoidCallback onDoubleTapCenter;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  // ── Double-tap seek ────────────────────────────────────────────────
  // Position du 2e tap (fournie par onDoubleTapDown — onDoubleTap seul
  // ne donne pas de coordonnées). Sert à décider gauche/centre/droite.
  Offset _doubleTapPos = Offset.zero;
  // Secondes CUMULÉES affichées dans le flash (façon YouTube : des
  // double-taps rapprochés du même côté s'additionnent : 10, 20, 30…).
  // 0 = aucun flash affiché.
  int _seekFlashSecs = 0;
  bool _seekFlashForward = true;
  Timer? _seekFlashTimer;

  // ── Glissés verticaux (volume / luminosité) ────────────────────────
  _VerticalDragMode _vDrag = _VerticalDragMode.none;
  Timer? _hudLingerTimer;
  // Valeurs pilotées par le doigt. Le volume est relu au début de
  // chaque drag (le player peut avoir changé entre-temps) ; la
  // luminosité est lue UNE fois au montage (voir initState) puis
  // entretenue ici — le plugin n'a pas de « valeur courante » synchrone.
  double _volume = 100;
  double _brightness = 0.5;
  // `true` dès que l'utilisateur a réellement modifié la luminosité :
  // on ne restaure la luminosité système au dispose QUE dans ce cas
  // (évite un appel plateforme parasite à chaque recréation de la
  // surface, notamment au zap TikTok où la couche est remontée).
  bool _brightnessTouched = false;

  // ── Scrub horizontal (VOD) ─────────────────────────────────────────
  bool _scrubbing = false;
  double _scrubDx = 0;
  Duration _scrubStart = Duration.zero;
  Duration _scrubTarget = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Luminosité COURANTE de l'app lue une fois au montage : le premier
    // glissé part ainsi de la vraie valeur, pas d'un 0.5 arbitraire.
    // try/catch : sur TV / desktop le plugin peut ne pas répondre — on
    // garde alors le défaut, le geste reste simplement approximatif.
    unawaited(() async {
      try {
        final double b = await ScreenBrightness.instance.application;
        if (mounted) _brightness = b.clamp(0.0, 1.0).toDouble();
      } catch (_) {
        // Plugin indisponible : défaut conservé, aucun impact lecture.
      }
    }());
  }

  @override
  void dispose() {
    _seekFlashTimer?.cancel();
    _hudLingerTimer?.cancel();
    // Comportement standard : la luminosité forcée pendant la lecture ne
    // doit PAS survivre au lecteur — on rend la main au système en
    // quittant. Fire-and-forget (dispose ne peut pas attendre).
    if (_brightnessTouched) {
      unawaited(ScreenBrightness.instance
          .resetApplicationScreenBrightness()
          .catchError((Object _) {}));
    }
    super.dispose();
  }

  // ── Double-tap ─────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapPos = d.localPosition;

  void _onDoubleTap() {
    final double width = context.size?.width ?? 0;
    if (width <= 0) return;
    final double x = _doubleTapPos.dx / width;
    // Zones standard : ~tiers gauche / droit = seek, bande centrale =
    // play/pause. Les seuils 0.35/0.65 élargissent légèrement le centre
    // pour éviter les seeks accidentels près du bouton play.
    if (x < 0.35) {
      _doubleTapSeek(forward: false);
    } else if (x > 0.65) {
      _doubleTapSeek(forward: true);
    } else {
      widget.onDoubleTapCenter();
    }
  }

  void _doubleTapSeek({required bool forward}) {
    // Live (pas de durée réelle) : geste inerte — surtout PAS de seek
    // dans la fenêtre de buffer, ça décalerait le direct sans feedback.
    if (!widget.seekEnabled) return;
    final Duration dur = widget.duration();
    if (dur <= Duration.zero) return;

    Duration target =
        widget.position() + Duration(seconds: forward ? 10 : -10);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    widget.onSeekTo(target);

    // Flash cumulatif : même côté + flash encore visible → on additionne.
    final bool sameSide = _seekFlashSecs != 0 && _seekFlashForward == forward;
    setState(() {
      _seekFlashForward = forward;
      _seekFlashSecs = (sameSide ? _seekFlashSecs : 0) + 10;
    });
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _seekFlashSecs = 0);
    });
  }

  // ── Glissés verticaux ──────────────────────────────────────────────

  void _onVerticalDragStart(DragStartDetails d) {
    final double width = context.size?.width ?? 0;
    if (width <= 0) return;
    final bool right = d.localPosition.dx >= width / 2;
    _hudLingerTimer?.cancel();
    setState(() {
      _vDrag = right ? _VerticalDragMode.volume : _VerticalDragMode.brightness;
      // Volume relu au départ du geste : il a pu changer côté player.
      if (right) _volume = widget.volume().clamp(0.0, 100.0).toDouble();
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_vDrag == _VerticalDragMode.none) return;
    final double height = context.size?.height ?? 0;
    if (height <= 0) return;
    // Glisser ~70 % de la hauteur = toute l'échelle (sensibilité MX
    // Player). dy est négatif vers le HAUT → on inverse : haut = plus.
    final double delta = -d.delta.dy / (height * 0.7);
    setState(() {
      if (_vDrag == _VerticalDragMode.volume) {
        _volume = (_volume + delta * 100).clamp(0.0, 100.0).toDouble();
        widget.onSetVolume(_volume);
      } else {
        _brightness = (_brightness + delta).clamp(0.0, 1.0).toDouble();
        _brightnessTouched = true;
        // Fire-and-forget : attendre chaque aller-retour plateforme
        // saccaderait le geste ; en cas d'échec (plugin absent) la
        // jauge reste cohérente et le drag inoffensif.
        unawaited(ScreenBrightness.instance
            .setApplicationScreenBrightness(_brightness)
            .catchError((Object _) {}));
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails _) => _endVerticalDrag();
  void _onVerticalDragCancel() => _endVerticalDrag();

  void _endVerticalDrag() {
    if (_vDrag == _VerticalDragMode.none) return;
    // La jauge reste affichée un court instant après le relâchement
    // (lecture confortable de la valeur finale), puis s'efface.
    _hudLingerTimer?.cancel();
    _hudLingerTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _vDrag = _VerticalDragMode.none);
    });
  }

  // ── Scrub horizontal ───────────────────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails d) {
    final Duration dur = widget.duration();
    if (dur <= Duration.zero) return;
    setState(() {
      _scrubbing = true;
      _scrubDx = 0;
      _scrubStart = widget.position();
      _scrubTarget = _scrubStart;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (!_scrubbing) return;
    final double width = context.size?.width ?? 0;
    final Duration dur = widget.duration();
    if (width <= 0 || dur <= Duration.zero) return;
    _scrubDx += d.delta.dx;
    // Toute la largeur d'écran = ±3 min de contenu (borné à la durée) :
    // précision avant tout — pour traverser un film entier, la barre de
    // progression de l'overlay existe déjà.
    final Duration window =
        dur < const Duration(minutes: 3) ? dur : const Duration(minutes: 3);
    Duration target = _scrubStart +
        Duration(
          milliseconds: (_scrubDx / width * window.inMilliseconds).round(),
        );
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    setState(() => _scrubTarget = target);
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (!_scrubbing) return;
    // Seek UNIQUE au relâchement — même philosophie que la barre de
    // progression de l'écran : on ne spamme pas libmpv pendant le drag.
    widget.onSeekTo(_scrubTarget);
    setState(() => _scrubbing = false);
  }

  void _onHorizontalDragCancel() {
    if (!_scrubbing) return;
    setState(() => _scrubbing = false);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool vertical = widget.verticalGesturesEnabled;
    final bool seek = widget.seekEnabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: _onDoubleTap,
      // Handlers NULL quand le geste est désactivé : aucun recognizer
      // n'est créé → le PageView de zap TikTok garde ses swipes
      // verticaux, et le scrub n'existe pas en live (cf. en-tête).
      onVerticalDragStart: vertical ? _onVerticalDragStart : null,
      onVerticalDragUpdate: vertical ? _onVerticalDragUpdate : null,
      onVerticalDragEnd: vertical ? _onVerticalDragEnd : null,
      onVerticalDragCancel: vertical ? _onVerticalDragCancel : null,
      onHorizontalDragStart: seek ? _onHorizontalDragStart : null,
      onHorizontalDragUpdate: seek ? _onHorizontalDragUpdate : null,
      onHorizontalDragEnd: seek ? _onHorizontalDragEnd : null,
      onHorizontalDragCancel: seek ? _onHorizontalDragCancel : null,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          // Feedbacks visuels — IgnorePointer : jamais dans le chemin
          // tactile, ils ne doivent voler ni tap ni drag.
          if (_seekFlashSecs != 0) IgnorePointer(child: _buildSeekFlash()),
          if (_vDrag != _VerticalDragMode.none)
            IgnorePointer(child: _buildVerticalGauge()),
          if (_scrubbing) IgnorePointer(child: _buildScrubPreview()),
        ],
      ),
    );
  }

  // ── Feedbacks visuels ──────────────────────────────────────────────
  //  Même vocabulaire que l'overlay existant : fonds noirs translucides
  //  (withValues alpha), coins arrondis, accent AppColors, police
  //  numeric — pour que les HUD paraissent natifs du lecteur.

  /// mm:ss (ou h:mm:ss) — même format que la barre de progression.
  static String _fmt(Duration d) {
    final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// Flash bref « ⏪ −10 s » / « +10 s ⏩ » du côté double-tapé.
  Widget _buildSeekFlash() {
    final bool fwd = _seekFlashForward;
    return Align(
      alignment: Alignment(fwd ? 0.55 : -0.55, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              fwd ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 2),
            Text(
              fwd ? '+$_seekFlashSecs s' : '−$_seekFlashSecs s',
              style: AppTextStyles.numeric.copyWith(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Jauge verticale volume (droite) / luminosité (gauche), du côté du
  /// doigt, avec icône adaptée au niveau et pourcentage.
  Widget _buildVerticalGauge() {
    final bool isVolume = _vDrag == _VerticalDragMode.volume;
    final double fraction =
        (isVolume ? _volume / 100 : _brightness).clamp(0.0, 1.0).toDouble();
    final IconData icon = isVolume
        ? (_volume <= 0
            ? Icons.volume_off_rounded
            : _volume < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded)
        : Icons.brightness_6_rounded;
    return Align(
      alignment: Alignment(isVolume ? 0.75 : -0.75, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 10),
            SizedBox(
              width: 5,
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction,
                      widthFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(fraction * 100).round()}',
              style: AppTextStyles.numeric.copyWith(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aperçu du scrub : delta signé + temps cible / durée, au-dessus du
  /// centre pour ne pas masquer l'action à l'écran.
  Widget _buildScrubPreview() {
    final Duration dur = widget.duration();
    final Duration diff = _scrubTarget - _scrubStart;
    final bool ahead = diff >= Duration.zero;
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${ahead ? '+' : '−'}${_fmt(ahead ? diff : -diff)}',
              style: AppTextStyles.numeric.copyWith(
                color: AppColors.accent,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmt(_scrubTarget)} / ${_fmt(dur)}',
              style: AppTextStyles.numeric.copyWith(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
