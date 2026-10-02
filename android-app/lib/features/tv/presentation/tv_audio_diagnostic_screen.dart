// =========================================================
//  tv_audio_diagnostic_screen.dart — « Diagnostic du son »
// =========================================================
//  Lecture des rapports locaux (une fiche par chaîne) et des
//  interrupteurs COUPÉS par défaut :
//    • mesurer le spectre (copie le PCM, ne le filtre pas) ;
//    • réessayer FFmpeg à la prochaine chaîne ;
//    • essayer le décodeur AAC de la box à la prochaine chaîne ;
//    • (02/10/2026) « Mode : normal forcé » — correctif candidat H1 :
//      remettre le système Android en mode normal avant chaque ouverture ;
//    • (02/10/2026) « Type : film / musique / parole » — essai H2 : le type
//      de contenu déclaré au système ;
//    • (02/10/2026) « Jouer le son témoin » — H4 : un fichier AAC de l'APK,
//      lu par le MÊME lecteur sans réseau, pour séparer « c'est la source »
//      de « c'est l'appareil ou l'app ». Sa fiche s'appelle « Son témoin ».
//  Rien n'est envoyé au panel : le heartbeat n'a pas de champ pour ça.
//  Style : les mêmes TvTokens / TvDimens que la boîte noire.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../features/player/data/audio_diag_prefs.dart';
import '../../../features/player/data/audio_report_store.dart';
import '../../../features/player/domain/audio_report_book.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvAudioDiagnosticScreen extends StatefulWidget {
  const TvAudioDiagnosticScreen({super.key});

  @override
  State<TvAudioDiagnosticScreen> createState() => _TvAudioDiagnosticScreenState();
}

class _TvAudioDiagnosticScreenState extends State<TvAudioDiagnosticScreen> {
  AudioReportBook _book = AudioReportBook.empty;
  bool _loading = true;
  bool _probe = false;
  bool _ffmpeg = false;
  bool _platform = false;
  bool _sessionWide = false;
  bool _androidFocus = false;
  bool _bgPause = false;
  bool _immediate = false;
  bool _modeNormal = false;
  String _content = NativeVideoController.contentFilm;

  // Son témoin : un lecteur natif caché (1 × 1 px), le temps du fichier.
  // Le même code que les chaînes : décodeur, sondes, focus, AudioTrack.
  NativeVideoController? _witness;
  Timer? _witnessTimer;
  String _witnessStatus = '';

  // Défilement à la télécommande, comme la Boîte noire : une fiche fait
  // vingt lignes et plus, la ligne « Cycle » est en bas. Sans ceci, Bas
  // ne faisait rien (les fiches ne prennent pas le focus).
  final ScrollController _scroll = ScrollController();
  static const double _kRow = 24;

  @override
  void dispose() {
    _stopWitness(reason: null);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double px) {
    if (!_scroll.hasClients) return;
    final double target =
        (_scroll.offset + px).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _scrollBy(_kRow * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_scroll.hasClients && _scroll.offset <= 0) {
        return KeyEventResult.ignored; // remonte le focus vers les boutons
      }
      _scrollBy(-_kRow * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.channelDown) {
      _scrollBy(_kRow * 15);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelUp) {
      _scrollBy(-_kRow * 15);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _probe = NativeVideoController.audioProbeEnabled;
    _ffmpeg = NativeVideoController.keepFfmpegAudio;
    _platform = NativeVideoController.preferPlatformAac;
    _sessionWide = NativeVideoController.sessionWideFallback;
    _androidFocus = NativeVideoController.androidAudioFocus;
    _bgPause = NativeVideoController.backgroundPauseOnly;
    _immediate = NativeVideoController.immediateHandoff;
    _modeNormal = NativeVideoController.forceNormalAudioMode;
    _content = NativeVideoController.audioContentType;
    // Le libellé vient de la mémoire Dart. On le repousse au lecteur
    // déjà ouvert, pour que « mesuré » et la sonde native disent la même chose.
    NativeVideoController.pushAudioDiagFlags();
    _load();
  }

  Future<void> _toggleSessionWide() async {
    final bool next = !_sessionWide;
    setState(() => _sessionWide = next);
    await AudioDiagPrefs.setSessionWideFallback(next);
  }

  Future<void> _toggleImmediate() async {
    final bool next = !_immediate;
    setState(() => _immediate = next);
    await AudioDiagPrefs.setImmediateHandoff(next);
  }

  Future<void> _toggleAndroidFocus() async {
    final bool next = !_androidFocus;
    setState(() => _androidFocus = next);
    await AudioDiagPrefs.setAndroidFocus(next);
  }

  Future<void> _toggleBgPause() async {
    final bool next = !_bgPause;
    setState(() => _bgPause = next);
    await AudioDiagPrefs.setBackgroundPauseOnly(next);
  }

  Future<void> _toggleModeNormal() async {
    final bool next = !_modeNormal;
    setState(() => _modeNormal = next);
    BlackBox.instance.info(
      'SON',
      next
          ? 'Réglage : « Mode : normal forcé » ALLUMÉ (le mode système appel sera remis à normal à la prochaine ouverture)'
          : 'Réglage : « Mode : normal forcé » coupé (défaut, on ne touche pas au système)',
    );
    await AudioDiagPrefs.setForceNormalMode(next);
  }

  Future<void> _cycleContent() async {
    final String next = AudioDiagPrefs.nextContentType(_content);
    setState(() => _content = next);
    BlackBox.instance.info('SON', 'Réglage : type déclaré au système = « $next »');
    await AudioDiagPrefs.setContentType(next);
  }

  Future<void> _load() async {
    final AudioReportBook book = await AudioReportStore.instance.load();
    if (!mounted) return;
    setState(() {
      _book = book;
      _loading = false;
    });
  }

  Future<void> _toggleProbe() async {
    final bool next = !_probe;
    setState(() => _probe = next);
    await AudioDiagPrefs.setProbe(next);
  }

  Future<void> _toggleFfmpeg() async {
    final bool next = !_ffmpeg;
    setState(() => _ffmpeg = next);
    await AudioDiagPrefs.setKeepFfmpeg(next);
  }

  Future<void> _togglePlatform() async {
    final bool next = !_platform;
    setState(() => _platform = next);
    await AudioDiagPrefs.setPreferPlatform(next);
  }

  Future<void> _clear() async {
    await AudioReportStore.instance.clear();
    await _load();
  }

  // ---- son témoin -----------------------------------------------------------

  /// Lance le fichier témoin dans un lecteur natif caché. Sa fiche porte
  /// le nom « Son témoin » (pas la chaîne en cours). Un seul à la fois.
  void _playWitness() {
    if (_witness != null) return;
    BlackBox.instance.info('SON', 'Témoin : lecture du son témoin intégré (10 s, sans réseau)');
    NativeVideoController.audioDiagChannelOverride = NativeVideoController.witnessLabel;
    final NativeVideoController c = NativeVideoController(
      initialUrl: NativeVideoController.witnessAssetUri,
      openAsVod: true,
    );
    c.addListener(_onWitnessChanged);
    setState(() {
      _witness = c;
      _witnessStatus = 'Témoin : lecture en cours (bruit, voix, sifflement grave → aigu, bruit)…';
    });
    // Filet : si « fin » n'arrive pas (erreur silencieuse), on arrête quand même.
    _witnessTimer?.cancel();
    _witnessTimer = Timer(const Duration(seconds: 16), () {
      _stopWitness(reason: 'Témoin : arrêté après 16 s (fin non reçue). Relire la fiche « Son témoin ».');
    });
  }

  void _onWitnessChanged() {
    final NativeVideoController? c = _witness;
    if (c == null) return;
    if (c.isEnded) {
      _stopWitness(reason: 'Témoin : lu jusqu\'au bout. Relire la fiche « Son témoin » ci-dessous.');
    } else if (c.hasError) {
      _stopWitness(reason: 'Témoin : le lecteur a signalé une erreur. Voir la boîte noire.');
    }
  }

  /// Rend le lecteur caché et la place de la chaîne en cours dans les fiches.
  void _stopWitness({required String? reason}) {
    _witnessTimer?.cancel();
    _witnessTimer = null;
    final NativeVideoController? c = _witness;
    if (c == null) return;
    c.removeListener(_onWitnessChanged);
    c.dispose();
    _witness = null;
    // Le natif envoie encore une ou deux lignes après dispose : on laisse
    // le nom « Son témoin » une seconde avant de le rendre.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (NativeVideoController.audioDiagChannelOverride ==
          NativeVideoController.witnessLabel) {
        NativeVideoController.audioDiagChannelOverride = null;
      }
    });
    if (reason != null) BlackBox.instance.info('SON', reason);
    if (!mounted) return;
    setState(() => _witnessStatus = reason ?? '');
    // La fiche du témoin arrive par le même chemin que les chaînes.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final NativeVideoController? witness = _witness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Diagnostic du son',
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Rapport local, une fiche par chaîne. Rien n\'est envoyé. '
          'Les interrupteurs sont coupés par défaut : le son ne change pas.',
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            _Toggle(
              label: _probe ? 'Spectre : mesuré' : 'Spectre : coupé',
              on: _probe,
              autofocus: true,
              onSelect: _toggleProbe,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: _ffmpeg ? 'FFmpeg : réessayer' : 'FFmpeg : défaut',
              on: _ffmpeg,
              onSelect: _toggleFfmpeg,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: witness == null ? 'Jouer le son témoin (10 s)' : 'Témoin : en cours…',
              on: witness != null,
              onSelect: _playWitness,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: 'Effacer',
              on: false,
              onSelect: _clear,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _Toggle(
              label: _platform ? 'Box AAC : essai' : 'Box AAC : coupé',
              on: _platform,
              onSelect: _togglePlatform,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: _sessionWide ? 'Repli : session entière' : 'Repli : par chaîne',
              on: _sessionWide,
              onSelect: _toggleSessionWide,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: _androidFocus ? 'Focus : Android' : 'Focus : Zuno',
              on: _androidFocus,
              onSelect: _toggleAndroidFocus,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: _bgPause ? 'Hors app : pause' : 'Hors app : arrêt',
              on: _bgPause,
              onSelect: _toggleBgPause,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _Toggle(
              label: _immediate ? 'Passage : tout de suite' : 'Passage : attendre',
              on: _immediate,
              onSelect: _toggleImmediate,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: _modeNormal ? 'Mode : normal forcé' : 'Mode : laisser',
              on: _modeNormal,
              onSelect: _toggleModeNormal,
            ),
            const SizedBox(width: 12),
            _Toggle(
              label: 'Type : $_content',
              on: _content != NativeVideoController.contentFilm,
              onSelect: _cycleContent,
            ),
          ],
        ),
        if (_witnessStatus.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _witnessStatus,
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.accentBright),
          ),
        ],
        // Lecteur caché du témoin : 1 × 1 px, le temps du fichier. Il faut
        // qu'il soit dans l'arbre pour que la vue native existe.
        if (witness != null)
          SizedBox(width: 1, height: 1, child: NativeVideoView(controller: witness)),
        const SizedBox(height: 8),
        Text(
          'Spectre : à la prochaine chaîne, mesure quatre points '
          '(décodeur, voix claire, silence, AudioTrack) sans modifier le son, '
          'avec l\'énergie > 4 kHz et la corrélation gauche/droite (une opposition '
          'de phase = voix du centre annulée). '
          'Son témoin : fichier AAC intégré (bruit, voix, sifflement, bruit) lu par le '
          'même lecteur sans réseau ; sa fiche s\'appelle « Son témoin ». Net ici et '
          'mauvais sur les chaînes = la source ; mauvais ici aussi = l\'appareil ou l\'app. '
          'Mode : « laisser » (défaut) = on ne touche pas au système ; « normal forcé » = '
          'si Android est resté en mode appel (haut-parleur d\'appel, Bluetooth SCO), on '
          'le remet à normal avant chaque ouverture. Type : « film » (défaut) / « musique » / '
          '« parole » = ce que l\'app déclare au système (certaines TV traitent le « film » '
          'autrement). '
          'FFmpeg : réessaie le décodeur logiciel ; s\'il ne démarre pas en 8 s, '
          'la box reprend. Box AAC : à la prochaine chaîne, l\'AAC passe par le '
          'décodeur de la box (comme ExoPlayer). S\'il échoue, FFmpeg reprend '
          'cette ouverture. Repli : « par chaîne » (défaut) = une panne FFmpeg '
          'n\'envoie à la box que la chaîne concernée ; « session entière » = '
          'ancien comportement. Focus : « Zuno » (défaut) = jamais de baisse de volume '
          'quand une autre app demande le son ; « Android » = ancien comportement '
          '(baisse à 20 %). Hors app : « arrêt » (défaut) = en quittant l\'app le son '
          'est coupé et rendu ; « pause » = ancien comportement. Passage : « attendre » '
          '(défaut) = la chaîne suivante n\'ouvre que lorsque l\'AudioTrack précédent '
          'est rendu ; « tout de suite » = ancien comportement.',
          style: TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? Center(
                  child: Text(
                    'Lecture…',
                    style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim),
                  ),
                )
              : _book.entries.isEmpty
                  ? Text(
                      'Aucun rapport. Ouvre une chaîne : le lecteur note le codec, '
                      'le décodeur et la sortie. Le spectre n\'est mesuré que si '
                      'l\'interrupteur est allumé.',
                      style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
                    )
                  : Focus(
                      onKeyEvent: _onKey,
                      child: Builder(builder: (BuildContext context) {
                        final bool focused = Focus.of(context).hasFocus;
                        return ListView.separated(
                      controller: _scroll,
                      itemCount: _book.entries.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int i) {
                        final AudioReportEntry e = _book.entries[i];
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: TvTokens.card,
                            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                            // Cadre doré quand la liste a le focus : Haut/Bas
                            // défilent, CH+/CH− changent de page.
                            border: Border.all(
                                color: focused ? TvTokens.accent : TvTokens.lineSoft),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                e.channel,
                                style: TextStyle(
                                  fontSize: TvDimens.title,
                                  fontWeight: FontWeight.w700,
                                  color: TvTokens.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                e.body,
                                style: TvTokens.mono(
                                  TvDimens.caption,
                                  weight: FontWeight.w400,
                                  color: TvTokens.muted,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                        );
                      }),
                    ),
        ),
        const SizedBox(height: 6),
        Text(
          'HAUT/BAS : défiler · CH+/CH− : page',
          style: TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.on,
    required this.onSelect,
    this.autofocus = false,
  });

  final String label;
  final bool on;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: () {
        onSelect();
      },
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.accent
            : (on ? TvTokens.sel : TvTokens.card);
        final Color fg = focused ? TvTokens.onAccent : TvTokens.accentBright;
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(color: focused ? TvTokens.accent : TvTokens.lineSoft),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: TvDimens.body,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        );
      },
    );
  }
}
