// =========================================================
//  tv_channel_guide_screen.dart — Guide d'UNE chaîne (10-foot)
// =========================================================
//  Ouvert depuis le lecteur (bouton Guide). Ce n'est PAS l'écran
//  téléphone `ChannelProgramsScreen` : là-bas les textes font 11 px,
//  le focus D-pad n'existe pas, et « Replay » ouvrait le lecteur
//  mobile (image noire sur beaucoup de box).
//
//  Ici : gros caractères, ligne dorée sous le focus, programme en
//  cours amené au milieu. OK ou Retour ferment le guide et laissent
//  la chaîne qui joue déjà. On ne lance pas un second lecteur.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../missed_show/domain/missed_summary.dart';
import '../../missed_show/presentation/missed_guide_details.dart';
import '../core/tv_back_guard.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';

class TvChannelGuideScreen extends StatefulWidget {
  const TvChannelGuideScreen({
    super.key,
    required this.channel,
    this.currentSummary,
  });

  final Channel channel;
  final MissedSummary? currentSummary;

  @override
  State<TvChannelGuideScreen> createState() => _TvChannelGuideScreenState();
}

class _TvChannelGuideScreenState extends State<TvChannelGuideScreen> {
  /// Hauteur fixe d'une ligne : la liste reste paresseuse et le
  /// défilement D-pad ne « saute » pas.
  static const double _rowExtent = 96;

  late Future<List<EpgProgram>> _future = _load();
  final ScrollController _scroll = ScrollController();
  final FocusNode _retryNode = FocusNode();
  final Map<int, FocusNode> _nodes = <int, FocusNode>{};
  bool _didFocusLive = false;
  bool _didFocusRetry = false;

  Future<List<EpgProgram>> _load() =>
      EpgRepository.instance.todayPrograms(widget.channel.id);

  FocusNode _nodeFor(int i) => _nodes.putIfAbsent(i, FocusNode.new);

  @override
  void dispose() {
    _scroll.dispose();
    _retryNode.dispose();
    for (final FocusNode n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _retry() {
    _didFocusLive = false;
    _didFocusRetry = false;
    setState(() => _future = _load());
  }

  void _close() {
    TvBackGuard.markHandled();
    Navigator.of(context).maybePop();
  }

  bool _isBack(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.goBack ||
      k == LogicalKeyboardKey.escape ||
      k == LogicalKeyboardKey.browserBack ||
      k == LogicalKeyboardKey.exit;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Seulement Retour. OK est laissé aux lignes (fermer) et au bouton
    // Réessayer : si on le captait ici, il fermerait le guide avant eux.
    if (_isBack(event.logicalKey)) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Le focus racine est déjà pris (pour que Retour marche). On le
  /// vole explicitement : `autofocus` ne gagne pas si un parent l'a déjà.
  void _focusRetry() {
    if (_didFocusRetry) return;
    _didFocusRetry = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _retryNode.requestFocus();
    });
  }

  /// Amène le programme en cours sous le focus, une seule fois
  /// (sinon chaque rebuild volerait la ligne que l'utilisateur
  /// est en train de lire).
  void _revealLive(List<EpgProgram> programs) {
    if (_didFocusLive) return;
    final DateTime now = DateTime.now();
    final int live = programs.indexWhere((EpgProgram p) => p.isLiveAt(now));
    if (live < 0) return;
    _didFocusLive = true;
    // 1) On scrolle d'abord (la ligne n'existe pas encore si elle est
    //    loin dans la journée). 2) Au frame suivant elle est construite,
    //    on peut lui donner le focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double target = (live * _rowExtent) - _rowExtent;
      final double max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(target.clamp(0.0, max));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nodeFor(live).requestFocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return TvShell(
      child: Focus(
        // Prend le focus tout de suite : sinon la touche Retour traverse
        // jusqu'au lecteur (et ferme la chaîne en même temps que le guide).
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(context.l10n.tvGuideBtn.toUpperCase(),
                style: TvTokens.ui(TvDimens.caption,
                    weight: FontWeight.w700,
                    color: TvTokens.accentBright,
                    spacing: 2)),
            const SizedBox(height: 6),
            Text(widget.channel.cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.display(TvDimens.headline, color: TvTokens.text)),
            const SizedBox(height: 4),
            Text(context.l10n.programsToday,
                style: TvTokens.ui(TvDimens.body, color: TvTokens.muted)),
            const SizedBox(height: 4),
            Text(context.l10n.tvGuideHint,
                style: TvTokens.ui(TvDimens.label, color: TvTokens.mutedDim)),
            MissedGuideDetails(summary: widget.currentSummary),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<EpgProgram>>(
                future: _future,
                builder: (BuildContext context,
                    AsyncSnapshot<List<EpgProgram>> snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _status(
                      icon: null,
                      title: context.l10n.tvGuideLoading,
                      spinning: true,
                    );
                  }
                  if (snap.hasError) {
                    _focusRetry();
                    return _status(
                      icon: Icons.error_outline_rounded,
                      title: context.l10n.programsNoneToday,
                      body: context.l10n.programsNoneHelp,
                      retry: true,
                    );
                  }
                  final List<EpgProgram> programs =
                      snap.data ?? const <EpgProgram>[];
                  if (programs.isEmpty) {
                    return _status(
                      icon: Icons.event_note_rounded,
                      title: context.l10n.programsNoneToday,
                      body: context.l10n.programsNoneHelp,
                    );
                  }
                  _revealLive(programs);
                  final DateTime now = DateTime.now();
                  return ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    itemExtent: _rowExtent,
                    itemCount: programs.length,
                    itemBuilder: (BuildContext context, int i) {
                      final EpgProgram p = programs[i];
                      final bool live = p.isLiveAt(now);
                      final bool past = !live &&
                          p.stopTime <= now.millisecondsSinceEpoch;
                      return _ProgramRow(
                        program: p,
                        live: live,
                        past: past,
                        focusNode: _nodeFor(i),
                        onSelect: _close,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chargement, erreur ou « pas de guide » : même gabarit, lisible
  /// à 3 m, avec Réessayer focusable quand un nouvel essai a un sens.
  Widget _status({
    required String title,
    IconData? icon,
    String? body,
    bool spinning = false,
    bool retry = false,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (spinning)
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: TvTokens.accent),
            )
          else
            Icon(icon ?? Icons.event_note_rounded,
                size: 52, color: TvTokens.accentBright),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: TvTokens.ui(TvDimens.title,
                  weight: FontWeight.w700, color: TvTokens.text)),
          if (body != null) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: 640,
              child: Text(body,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(TvDimens.body, color: TvTokens.muted)),
            ),
          ],
          if (retry) ...<Widget>[
            const SizedBox(height: 18),
            TvFocusable(
              focusNode: _retryNode,
              scale: TvFocusScale.none,
              onSelect: _retry,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Text(context.l10n.tvRetry,
                    style: TvTokens.ui(TvDimens.titleS,
                        weight: FontWeight.w700, color: TvTokens.accentBright)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({
    required this.program,
    required this.live,
    required this.past,
    required this.focusNode,
    required this.onSelect,
  });

  final EpgProgram program;
  final bool live;
  final bool past;
  final FocusNode focusNode;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    // Heure de début, courte, dans la pastille : on balaie le guide
    // sans lire la ligne entière. « LIVE » reste le seul mot, pour
    // repérer le programme en cours d'un coup d'œil.
    final DateTime start = program.startDateTime;
    final String hh =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final String badge = live ? context.l10n.badgeLive : hh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TvFocusBuilder(
        focusNode: focusNode,
        // Pas de zoom : dans une liste serrée, le scale rogne l'anneau
        // doré. Le fond + le contour suffisent à 3 m.
        scale: TvFocusScale.none,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color badgeBg = live
              ? TvTokens.live
              : (focused ? TvTokens.accent : TvTokens.sel);
          final Color badgeFg =
              (live || focused) ? TvTokens.onAccent : TvTokens.muted;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: focused ? TvTokens.sel : Colors.transparent,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: focused
                  ? Border.all(color: TvTokens.accent, width: TvDimens.focusOutline)
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 108,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(TvTokens.rSmall),
                  ),
                  child: Text(badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.caption,
                          weight: FontWeight.w800, color: badgeFg)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(program.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TvTokens.ui(TvDimens.titleS,
                              weight: FontWeight.w700,
                              color: focused
                                  ? TvTokens.accentBright
                                  : (past ? TvTokens.muted : TvTokens.text))),
                      const SizedBox(height: 4),
                      Text(
                        '${program.timeRangeShort}  ·  ${program.durationLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

