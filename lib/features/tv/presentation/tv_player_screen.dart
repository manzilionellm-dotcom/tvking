// =========================================================
//  tv_player_screen.dart — Lecteur plein écran TV (SurfaceView natif)
// =========================================================
//  Moteur = Media3 / ExoPlayer sur une vraie android.view.SurfaceView, via le
//  plugin local `native_video_player` (Hybrid Composition). PAS media_kit/mpv
//  NI flutter_vlc_player : les deux rendaient la vidéo dans une TEXTURE Flutter
//  et donnaient « son OK / image NOIRE » sur certaines box (trames HEVC
//  décodées par MediaCodec mais jamais affichées). Une SurfaceView native sort
//  la vidéo du chemin texture → l'image passe, comme dans IPTV Smarters & co.
//
//  Réglages stabilité (côté natif, cf. NativeVideoView.kt) :
//    1) décodage matériel MediaCodec + repli logiciel (decoder fallback) ;
//    2) gros tampon (min 5 s / max 30 s, démarrage 1,5 s) ;
//    3) watchdog 15 s : aucune progression → reconnexion auto (ré-ouvre l'URL).
//
//  D-pad : Haut/Bas (ou Ch+/Ch-) = zap, chiffres = n° de chaîne, OK = barre,
//  Back = quitter. Logo « The Few » affiché à l'ouverture / au zap.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../player/data/local_stream_relay.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import 'tv_components.dart';

class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  /// Liste pour le zap (Haut/Bas) — généralement la catégorie courante.
  final List<Channel> channels;
  final int startIndex;

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  late final NativeVideoController _controller;
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  Timer? _numTimer;
  Timer? _watchdog;
  Timer? _toastTimer;
  String _numBuffer = ''; // saisie d'un numéro de chaîne (touches 0-9)

  // ----- Enregistrement -----
  // Quand on enregistre, on fait passer la lecture par le MINI-RELAIS local
  // (LocalStreamRelay) : il ouvre UNE seule connexion vers le serveur IPTV et
  // recopie les octets À LA FOIS vers le lecteur ET vers le fichier .ts. Donc
  // le fournisseur ne voit qu'1 connexion (compatible max_connections=1) et le
  // fichier capture EXACTEMENT ce qui est à l'écran. Hors enregistrement, la
  // lecture reste DIRECTE (le relais n'est pas dans le chemin).
  Recording? _activeRecording;
  bool get _isRecording => _activeRecording != null;
  String? _relayPlayUrl; // URL locale 127.0.0.1 utilisée pendant l'enregistrement
  String? _toastMsg; // petit message éphémère (sauvegardé / vide / échec)

  // Anti-gel : on suit la progression réelle (position qui avance).
  DateTime _lastProgress = DateTime.now();
  Duration _lastPos = Duration.zero;
  bool _recovering = false;
  static const Duration _frozen = Duration(seconds: 15);
  static const Duration _watchEvery = Duration(seconds: 4);

  Channel get _current => widget.channels[_index];

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const List<LogicalKeyboardKey> _numpad = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  @override
  void initState() {
    super.initState();
    // Le décodage (MediaCodec matériel + repli logiciel), le tampon réseau et
    // le User-Agent sont gérés côté natif (NativeVideoView.kt). Ici on se
    // contente de piloter l'URL et d'écouter l'état.
    _controller = NativeVideoController(initialUrl: _current.streamUrl);
    _controller.addListener(_onPlayer);
    _open(reuse: true); // historique / présence pour la 1re chaîne
    // Chien de garde : aucune progression depuis 15 s → reconnexion.
    _watchdog = Timer.periodic(_watchEvery, (_) {
      if (!_recovering && DateTime.now().difference(_lastProgress) > _frozen) {
        _recover();
      }
    });
    // Garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _numTimer?.cancel();
    _watchdog?.cancel();
    _toastTimer?.cancel();
    // Si on quitte le lecteur en plein enregistrement : on finalise proprement
    // (arrêt du relais + clôture en base), sans toucher au controller détruit.
    if (_activeRecording != null) {
      final Recording rec = _activeRecording!;
      LocalStreamRelay.instance.stopRecording(rec.streamUrl ?? _current.streamUrl);
      RecordingRepository.instance.finishRecording(rec);
    }
    _controller.removeListener(_onPlayer);
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend(); // on ne regarde plus rien
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Écoute l'état du lecteur natif : progression (anti-gel), buffering (logo),
  // erreurs.
  void _onPlayer() {
    // Progression réelle → « pas gelé ».
    if (_controller.position != _lastPos) {
      _lastPos = _controller.position;
      _lastProgress = DateTime.now();
      _recovering = false;
    }
    // Logo tant qu'on bufferise OU que la 1re trame n'est pas encore dessinée
    // (au zap, firstFrame est remis à false → logo jusqu'à l'image suivante).
    final bool buffering = _controller.isBuffering || !_controller.firstFrame;
    if (mounted && buffering != _buffering) {
      setState(() => _buffering = buffering);
    }
    // Erreur / fin de flux live → reconnexion.
    if (_controller.hasError || _controller.isEnded) {
      _recover();
    }
  }

  void _open({bool reuse = false}) {
    _lastProgress = DateTime.now();
    _lastPos = Duration.zero;
    if (mounted) setState(() => _buffering = true);
    if (!reuse) {
      // Nouvelle chaîne → on charge la nouvelle URL dans le MÊME lecteur.
      _controller.setUrl(_current.streamUrl);
    }
    // Historique (reprise « Continuer à regarder », favoris, reco).
    RecentlyWatchedRepository.instance.record(_current.id);
    NowPlaying.instance.set(_current.cleanName);
    SubscriptionState.instance.syncWithBackend();
    _showOverlayTemporarily();
  }

  void _zap(int delta) {
    final int n = widget.channels.length;
    if (n <= 1) return;
    // On ne peut enregistrer qu'1 chaîne à la fois (1 connexion) : changer de
    // chaîne clôt et SAUVEGARDE l'enregistrement en cours.
    if (_isRecording) _finalizeRecording(resumeDirect: false);
    setState(() => _index = (_index + delta) % n);
    if (_index < 0) _index += n;
    _open();
  }

  void _recover() {
    if (_recovering) return;
    _recovering = true;
    _lastProgress = DateTime.now();
    // Ré-ouvre la MÊME source : l'URL locale du relais si on enregistre, sinon
    // l'URL directe. = reconnexion au direct sans casser l'enregistrement.
    _controller.setUrl(_relayPlayUrl ?? _current.streamUrl);
  }

  // ----- Enregistrement (bouton REC / touche média) -----

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _finalizeRecording(resumeDirect: true);
    } else {
      await _startRecording();
    }
    _showOverlayTemporarily();
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final String realUrl = _current.streamUrl;
    try {
      final String path = await RecordingRepository.instance
          .createFilePath(channelName: _current.cleanName);

      // 1) On bascule D'ABORD la lecture sur le relais : le lecteur lâche la
      //    connexion DIRECTE et le relais ouvre L'UNIQUE connexion vers le
      //    serveur. On évite ainsi d'avoir 2 connexions en même temps
      //    (incompatible avec les fournisseurs max_connections=1).
      final String localUrl =
          await LocalStreamRelay.instance.playUrlFor(realUrl);
      _relayPlayUrl = localUrl;
      _controller.setUrl(localUrl);

      // 2) On attache l'écriture fichier à CETTE MÊME session relais (pas de
      //    nouvelle connexion : le tee recopie juste les octets vers le .ts).
      final bool ok = await LocalStreamRelay.instance
          .startRecording(realUrl: realUrl, filePath: path);
      if (!ok) {
        _relayPlayUrl = null;
        _controller.setUrl(realUrl); // on revient au direct
        _flash('Échec démarrage enregistrement');
        return;
      }

      // 3) On enregistre la fiche en base (liste « Enregistrements »).
      final Recording rec = await RecordingRepository.instance.startRecording(
        channelId: _current.id,
        channelName: _current.cleanName,
        filePath: path,
        channelLogoUrl: _current.logoUrl,
        streamUrl: realUrl,
      );
      if (mounted) {
        setState(() => _activeRecording = rec);
        _flash('Enregistrement en cours…');
      }
    } catch (e) {
      _flash('Erreur enregistrement');
    }
  }

  /// Clôt l'enregistrement en cours. [resumeDirect] = on rebascule la lecture
  /// en direct (bouton stop) ; à false quand l'appelant va lui-même rouvrir
  /// une autre source (zap).
  Future<void> _finalizeRecording({required bool resumeDirect}) async {
    final Recording? rec = _activeRecording;
    if (rec == null) return;
    // UI immédiate : on n'est plus « en train d'enregistrer ».
    if (mounted) {
      setState(() => _activeRecording = null);
    } else {
      _activeRecording = null;
    }
    _relayPlayUrl = null;
    final String realUrl = rec.streamUrl ?? _current.streamUrl;
    int bytes = 0;
    try {
      bytes = await LocalStreamRelay.instance.stopRecording(realUrl);
      await RecordingRepository.instance.finishRecording(rec);
    } catch (_) {}
    if (resumeDirect && mounted) {
      _controller.setUrl(_current.streamUrl);
    }
    if (mounted) {
      _flash(bytes > 0
          ? 'Enregistrement sauvegardé (${_humanSize(bytes)})'
          : 'Enregistrement vide');
    }
  }

  // Petit message éphémère en bas de l'écran (~3 s).
  void _flash(String msg) {
    setState(() => _toastMsg = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Go';
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  // Affiche/masque la barre (OK télécommande OU tap sur l'écran tactile).
  void _toggleOverlay() {
    setState(() => _overlay = !_overlay);
    if (_overlay) _showOverlayTemporarily();
  }

  // Lecture/pause (touche média OU bouton tactile). setState pour rafraîchir
  // l'icône ▶/⏸ des contrôles tactiles.
  void _togglePlayPause() {
    if (_controller.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _showOverlayTemporarily();
    setState(() {});
  }

  // ----- Saisie d'un numéro de chaîne (0-9) → zap après ~1,5 s -----
  void _onDigit(int d) {
    if (_numBuffer.length < 4) _numBuffer += '$d';
    _numTimer?.cancel();
    _numTimer = Timer(const Duration(milliseconds: 1500), _jumpNumber);
    setState(() {});
  }

  void _jumpNumber() {
    final int? n = int.tryParse(_numBuffer);
    _numBuffer = '';
    if (n == null || n <= 0) { setState(() {}); return; }
    setState(() => _index = (n - 1).clamp(0, widget.channels.length - 1));
    _open();
  }

  bool _isPrev(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.channelUp ||
      k == LogicalKeyboardKey.pageUp ||
      k == LogicalKeyboardKey.mediaTrackPrevious;
  bool _isNext(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.channelDown ||
      k == LogicalKeyboardKey.pageDown ||
      k == LogicalKeyboardKey.mediaTrackNext;
  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.contextMenu ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight;

  // Télécommandes universelles : toutes les variantes mènent à l'action.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    // BACK / Retour télécommande (toutes variantes) → quitter le lecteur,
    // retour à la liste. On gère explicitement pour ne jamais rester coincé.
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) { _onDigit(di); return KeyEventResult.handled; }

    if (_isPrev(k)) { _zap(-1); return KeyEventResult.handled; }
    if (_isNext(k)) { _zap(1); return KeyEventResult.handled; }

    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRecord || k == LogicalKeyboardKey.keyR) {
      _toggleRecording();
      return KeyEventResult.handled;
    }
    if (_isOk(k)) {
      _toggleOverlay();
      return KeyEventResult.handled;
    }
    _showOverlayTemporarily();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        // TACTILE (TV/tablette à écran tactile) : tap = affiche/masque la
        // barre ; glissé vertical = zap. Les boutons de la barre captent leur
        // propre tap (ils gagnent l'arène des gestes) avant ce fond.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          onVerticalDragEnd: (DragEndDetails d) {
            final double v = d.primaryVelocity ?? 0;
            if (v < -250) {
              _zap(1); // glissé vers le HAUT → chaîne suivante
            } else if (v > 250) {
              _zap(-1); // glissé vers le BAS → chaîne précédente
            }
          },
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
              // Vidéo SurfaceView native plein écran (16:9 centré sur TV 16:9).
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: NativeVideoView(controller: _controller),
                ),
              ),
              // Écran de marque pendant l'ouverture / le zap / une reconnexion.
              if (_buffering)
                const ColoredBox(
                  color: TvTokens.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TvLogo(width: 200),
                        SizedBox(height: 28),
                        SizedBox(
                          width: 40, height: 40,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: TvTokens.gold),
                        ),
                      ],
                    ),
                  ),
                ),
              // Barre de chaînes + contrôles tactiles (auto-masqués).
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: TvDimens.focusAnim,
                child: IgnorePointer(
                  ignoring: !_overlay,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Boutons au doigt (tablette / TV tactile). Non
                        // focusables : le D-pad les ignore et zappe directement.
                        _TouchControls(
                          isPlaying: _controller.isPlaying,
                          isRecording: _isRecording,
                          onBack: () => Navigator.of(context).maybePop(),
                          onPrev: () => _zap(-1),
                          onNext: () => _zap(1),
                          onPlayPause: _togglePlayPause,
                          onRecord: _toggleRecording,
                        ),
                        _ChannelBar(channel: _current, index: _index),
                      ],
                    ),
                  ),
                ),
              ),
              // Numéro saisi à la télécommande (coin haut-droit).
              if (_numBuffer.isNotEmpty)
                Positioned(
                  top: TvDimens.safeV + 8,
                  right: TvDimens.safeH,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(_numBuffer,
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 4)),
                  ),
                ),
              // Pastille « ● REC » visible en permanence pendant l'enregistrement
              // (même quand la barre est masquée).
              if (_isRecording)
                Positioned(
                  top: TvDimens.safeV + 8,
                  left: TvDimens.safeH,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: TvTokens.live),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.fiber_manual_record_rounded,
                            color: TvTokens.live, size: 16),
                        const SizedBox(width: 8),
                        Text('REC',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: TvTokens.text)),
                      ],
                    ),
                  ),
                ),
              // Message éphémère (sauvegardé / vide / échec).
              if (_toastMsg != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: TvDimens.safeV + 120,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(_toastMsg!,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rangée de boutons ronds pour le TACTILE (tablette / TV à écran tactile) :
/// retour, chaîne −, lecture/pause, chaîne +. Volontairement NON focusables
/// (GestureDetector, pas TvFocusable) → la télécommande D-pad les ignore et
/// continue de zapper directement, ils ne servent qu'au doigt.
class _TouchControls extends StatelessWidget {
  const _TouchControls({
    required this.isPlaying,
    required this.isRecording,
    required this.onBack,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onRecord,
  });

  final bool isPlaying;
  final bool isRecording;
  final VoidCallback onBack;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _RoundButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 14),
          _RoundButton(icon: Icons.skip_previous_rounded, onTap: onPrev),
          const SizedBox(width: 14),
          _RoundButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: onPlayPause,
            big: true,
          ),
          const SizedBox(width: 14),
          _RoundButton(icon: Icons.skip_next_rounded, onTap: onNext),
          const SizedBox(width: 14),
          // Bouton ENREGISTRER : rouge plein quand on enregistre (= stop),
          // contour rouge sinon (= démarrer).
          _RoundButton(
            icon: isRecording
                ? Icons.stop_rounded
                : Icons.fiber_manual_record_rounded,
            onTap: onRecord,
            iconColor: TvTokens.live,
            highlight: isRecording,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.big = false,
    this.iconColor,
    this.highlight = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  final Color? iconColor;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final double d = big ? 68 : 54;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: highlight
              ? TvTokens.live.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
              color: highlight ? TvTokens.live : Colors.white24),
        ),
        child: Icon(icon,
            color: iconColor ?? TvTokens.text, size: big ? 38 : 28),
      ),
    );
  }
}

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.channel, required this.index});
  final Channel channel;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          TvDimens.safeH, 20, TvDimens.safeH, TvDimens.safeV + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64, height: 64,
            child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                ? Image.network(channel.logoUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _initials(channel))
                : _initials(channel),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  channel.cleanName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.headline,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (channel.isLive) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: TvTokens.live,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(context.l10n.tvLiveBadge,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      channel.category.trim().isEmpty
                          ? context.l10n.tvOthers
                          : channel.category.trim(),
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          color: TvTokens.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(context.l10n.tvZapHint,
              style: TextStyle(
                  fontSize: TvDimens.caption, color: TvTokens.mutedDim)),
        ],
      ),
    );
  }

  Widget _initials(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(
                fontSize: TvDimens.title,
                fontWeight: FontWeight.w800,
                color: TvTokens.muted)),
      );
}
