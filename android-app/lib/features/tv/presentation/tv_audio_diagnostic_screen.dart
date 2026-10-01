// =========================================================
//  tv_audio_diagnostic_screen.dart — « Diagnostic du son »
// =========================================================
//  Lecture des rapports locaux (une fiche par chaîne) et des
//  interrupteurs COUPÉS par défaut :
//    • mesurer le spectre (copie le PCM, ne le filtre pas) ;
//    • réessayer FFmpeg à la prochaine chaîne ;
//    • essayer le décodeur AAC de la box à la prochaine chaîne.
//  Rien n'est envoyé au panel : le heartbeat n'a pas de champ pour ça.
//  Style : les mêmes TvTokens / TvDimens que la boîte noire.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

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

  // Défilement à la télécommande, comme la Boîte noire : une fiche fait
  // vingt lignes et plus, la ligne « Cycle » est en bas. Sans ceci, Bas
  // ne faisait rien (les fiches ne prennent pas le focus).
  final ScrollController _scroll = ScrollController();
  static const double _kRow = 24;

  @override
  void dispose() {
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
    _load();
  }

  Future<void> _toggleSessionWide() async {
    final bool next = !_sessionWide;
    setState(() => _sessionWide = next);
    await AudioDiagPrefs.setSessionWideFallback(next);
  }

  bool _androidFocus = false;
  bool _bgPause = false;
  bool _immediate = false;

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

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Spectre : à la prochaine chaîne, mesure quatre points '
          '(décodeur, voix claire, silence, AudioTrack) sans modifier le son. '
          'FFmpeg : réessaie le décodeur logiciel ; s\'il ne démarre pas en 8 s, '
          'la box reprend. Box AAC : à la prochaine chaîne, l\'AAC passe par le '
          'décodeur de la box (comme ExoPlayer). S\'il échoue, FFmpeg reprend '
          'cette ouverture. Repli : « par chaîne » (défaut) = une panne FFmpeg '
          'n\'envoie à la box que la chaîne concernée ; « session entière » = '
          'ancien comportement, toutes les chaînes passent à la box après une '
          'seule panne. Focus : « Zuno » (défaut) = jamais de baisse de volume '
          'quand une autre app ou un bip demande le son (le son « dans un trou ») ; '
          '« Android » = ancien comportement (baisse à 20 %). Hors app : '
          '« arrêt » (défaut) = en quittant l\'app le son est coupé et rendu, la '
          'chaîne est rouverte au retour ; « pause » = ancien comportement. '
          'Passage : « attendre » (défaut) = on n\'ouvre la chaîne suivante '
          'que lorsque l\'AudioTrack précédent est vraiment rendu (sinon deux '
          'sons se mélangent après beaucoup de zaps) ; « tout de suite » = '
          'ancien comportement.',
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
