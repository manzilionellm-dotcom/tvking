// =========================================================
//  tv_tivimate_guide_screen.dart — Grille EPG « TiviMate » (§4 de la fiche)
// =========================================================
//  La grille horaire façon TiviMate : chaînes en LIGNES (n° + logo + nom),
//  heures en COLONNES, ligne « maintenant » verticale fine. Navigation
//  100 % D-pad :
//    • Haut/Bas       : changer de chaîne (cellule chaîne à gauche) ;
//    • Gauche/Droite  : DÉCALER la fenêtre de temps de ±30 min (boutons) ;
//    • OK sur chaîne  : regarder en direct ;
//    • OK sur case    : direct (en cours) / revoir (passé + archive).
//
//  COULEURS IDENTIQUES à TiviMate : fond #000000, cellule à venir #2A2E35,
//  passé assombri #20242B, EN COURS teinté accent, focus = pill blanc plein
//  (texte noir), chaîne active = n°/nom bleu. SEUL le logo = SEVEN.
//
//  Même MÉCANIQUE que la grille native (pagination getChannelsPage,
//  programmes chargés par ligne visible via programsBetween). AUCUN contact
//  media_kit : la lecture passe par TvPlayerScreen (natif).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../channels/domain/channel.dart';
import '../../epg/data/catchup_url_builder.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';

// ---- Palette TiviMate (tokens §1 de la fiche) ----
const Color _tmBg = Color(0xFF000000);
const Color _tmPanel = Color(0xFF12171C);
const Color _tmCellFuture = Color(0xFF2A2E35); // cellule à venir
const Color _tmCellPast = Color(0xFF20242B); // cellule passée (assombrie)
const Color _tmAccent = Color(0xFF0A84FF); // accent bleu marque
const Color _tmText = Color(0xFFFFFFFF);
const Color _tmText2 = Color(0xFFB8BDC4);
const Color _tmText3 = Color(0xFF6B7178);

class TvTivimateGuideScreen extends StatefulWidget {
  const TvTivimateGuideScreen({super.key});

  @override
  State<TvTivimateGuideScreen> createState() => _TvTivimateGuideScreenState();
}

class _TvTivimateGuideScreenState extends State<TvTivimateGuideScreen> {
  // ----- Géométrie -----
  static const double _chanColW = 260; // colonne chaînes (n° + logo + nom)
  static const double _pxPerMin = 5.4; // 180 min → 972 px
  static const int _windowMin = 180; // fenêtre visible : 3 h
  static const double _rowH = 64;
  static const int _kPageSize = 60;

  // ----- Chaînes (paginées) -----
  final List<Channel> _channels = <Channel>[];
  int _cursor = 0;
  bool _hasMore = true;
  bool _loading = false;

  // ----- Fenêtre de temps -----
  late DateTime _windowStart = _floorHalfHour(DateTime.now());
  Timer? _clock;

  static DateTime _floorHalfHour(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);

  // Les futures EPG des lignes sont MÉMORISÉS (cf. _GuideRowState) : sans
  // ce signal, un guide ouvert PENDANT un import EPG (1er lancement,
  // refresh quotidien) restait figé à vide tant qu'on ne décalait pas la
  // fenêtre. Chaque lot inséré par l'import incrémente la génération →
  // les lignes re-requêtent.
  StreamSubscription<void>? _epgSub;
  int _epgGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _epgSub = EpgRepository.instance.changes.listen((_) {
      if (mounted) setState(() => _epgGeneration++);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _epgSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    final ({List<Channel> channels, int nextCursor, bool hasMore}) page =
        await PlaylistRepository.instance
            .getChannelsPage(afterLocalId: _cursor, limit: _kPageSize);
    if (!mounted) return;
    setState(() {
      _channels.addAll(page.channels);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    });
    _loading = false;
  }

  void _shiftWindow(int minutes) {
    final DateTime now = DateTime.now();
    final DateTime lo = _floorHalfHour(now.subtract(const Duration(hours: 1)));
    final DateTime hi = _floorHalfHour(now.add(const Duration(hours: 24)));
    DateTime next = _windowStart.add(Duration(minutes: minutes));
    if (next.isBefore(lo)) next = lo;
    if (next.isAfter(hi)) next = hi;
    if (next != _windowStart) setState(() => _windowStart = next);
  }

  void _play(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: _channels, startIndex: index),
      ),
    );
  }

  /// ARCHIVABLE (invariant dans le temps) : le fournisseur expose-t-il une
  /// archive pour cette émission ? La garde temporelle (« pas encore
  /// commencée ») est évaluée AU MOMENT VOULU par les appelants (_block à
  /// chaque build, _onBlock à l'appui) — la stocker ici figeait le drapeau
  /// dans les tuples mémorisés des lignes (revue de code).
  bool _canReplay(Channel channel, EpgProgram p) {
    return CatchupUrlBuilder.build(channel: channel, program: p) != null;
  }

  void _onBlock(int channelIndex, Channel channel, EpgProgram p) {
    final DateTime now = DateTime.now();
    final bool onAir = p.startTime <= now.millisecondsSinceEpoch &&
        now.millisecondsSinceEpoch < p.stopTime;
    if (onAir) {
      _play(channelIndex);
      return;
    }
    // Émission à venir : jamais de replay (garde temporelle, ex-_canReplay).
    final bool started = p.startTime <= now.millisecondsSinceEpoch;
    final String? url = (started && _canReplay(channel, p))
        ? CatchupUrlBuilder.build(channel: channel, program: p)
        : null;
    if (url != null) {
      final Channel replay = Channel(
        id: '${channel.id}#catchup${p.startTime}',
        name: '${channel.cleanName} · ${p.title}',
        category: channel.category,
        streamUrl: url,
        isLive: false,
        playlistId: channel.playlistId,
        logoUrl: channel.logoUrl,
        currentProgram: p.title,
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TvPlayerScreen(channels: <Channel>[replay], startIndex: 0),
        ),
      );
      return;
    }
    _toast(p.startDateTime.isAfter(now)
        ? 'Programme à venir'
        : 'Replay indisponible');
  }

  void _toast(String msg) {
    // Toast maison via l'Overlay racine : il n'y a AUCUN Scaffold dans
    // l'arbre TV (TvShell = Material transparent) → le SnackBar d'avant ne
    // s'affichait jamais. Cf. showTvToast (tv_components.dart).
    showTvToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final int startMs = _windowStart.millisecondsSinceEpoch;
    final int endMs = startMs + _windowMin * 60 * 1000;
    final double timelineW = _windowMin * _pxPerMin;
    final double nowDx =
        (DateTime.now().millisecondsSinceEpoch - startMs) / 60000 * _pxPerMin;
    final bool nowVisible = nowDx >= 0 && nowDx <= timelineW;

    return Container(
      color: _tmBg,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ----- En-tête : titre + date/heure (bleu) + heures -----
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: _chanColW,
                      child: Row(
                        children: <Widget>[
                          Text(
                            _dateLabel(DateTime.now()),
                            style: const TextStyle(
                                color: _tmAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          _ShiftChip(
                              icon: Icons.chevron_left_rounded,
                              onSelect: () => _shiftWindow(-30)),
                          const SizedBox(width: 6),
                          _ShiftChip(
                              icon: Icons.chevron_right_rounded,
                              onSelect: () => _shiftWindow(30)),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 22,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            for (int m = 0; m <= _windowMin - 30; m += 30)
                              Positioned(
                                left: m * _pxPerMin,
                                top: 0,
                                child: Text(
                                  _labelAt(
                                      _windowStart.add(Duration(minutes: m))),
                                  style: const TextStyle(
                                      color: _tmText3,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            if (nowVisible)
                              Positioned(
                                left: nowDx - 0.5,
                                top: 0,
                                bottom: 0,
                                // Ligne NOW = trait fin blanc translucide (§4).
                                child: Container(
                                    width: 1,
                                    color: Colors.white
                                        .withValues(alpha: 0.55)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Haut/bas : chaîne · gauche/droite : ±30 min · OK : regarder',
                  style: const TextStyle(color: _tmText3, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // ----- Lignes chaînes -----
                Expanded(
                  child: _channels.isEmpty
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: _tmAccent))
                      : ListView.builder(
                          addAutomaticKeepAlives: false,
                          itemExtent: _rowH + 6,
                          itemCount: _channels.length,
                          itemBuilder: (BuildContext context, int i) {
                            if (i >= _channels.length - 12) _loadMore();
                            final int idx = i;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _GuideRow(
                                channel: _channels[i],
                                number: i + 1,
                                autofocus: i == 0,
                                startMs: startMs,
                                endMs: endMs,
                                pxPerMin: _pxPerMin,
                                chanColW: _chanColW,
                                rowH: _rowH,
                                nowDx: nowVisible ? nowDx : null,
                                onPlay: () => _play(idx),
                                epgGeneration: _epgGeneration,
                                canReplay: (EpgProgram p) =>
                                    _canReplay(_channels[idx], p),
                                onBlock: (EpgProgram p) =>
                                    _onBlock(idx, _channels[idx], p),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _labelAt(DateTime t) {
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _dateLabel(DateTime t) {
    const List<String> days = <String>[
      'lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'
    ];
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${t.day} · $h:$m';
  }
}

/// Une LIGNE de la grille : cellule chaîne (n° + logo + nom, focusable) +
/// blocs de programmes focusables (OK = direct / revoir).
///
/// FLUIDITÉ — StatefulWidget avec FUTURE MÉMORISÉ (même patron que la
/// grille Timeline, tv_timeline_guide_screen.dart) : en Stateless, le
/// FutureBuilder recréait sa requête `programsBetween` à CHAQUE build.
/// Or l'écran entier se reconstruit toutes les 30 s (tic de la ligne
/// « maintenant ») et à chaque décalage de fenêtre → chaque tic
/// relançait une requête SQLite PAR LIGNE VISIBLE (~14 requêtes/30 s)
/// et re-résolvait les FutureBuilders (flash de blocs vides). Le future
/// ne se recrée que si la chaîne OU la fenêtre change (didUpdateWidget).
/// Au passage, `canReplay` (construction d'URL catch-up) est calculé UNE
/// fois par programme au retour de la requête — plus ~70-110 appels par
/// tic dans les builders.
class _GuideRow extends StatefulWidget {
  const _GuideRow({
    required this.channel,
    required this.number,
    required this.autofocus,
    required this.startMs,
    required this.endMs,
    required this.pxPerMin,
    required this.chanColW,
    required this.rowH,
    required this.nowDx,
    required this.onPlay,
    required this.epgGeneration,
    required this.canReplay,
    required this.onBlock,
  });

  final Channel channel;
  final int number;
  final bool autofocus;
  final int startMs;
  final int endMs;
  final double pxPerMin;
  final double chanColW;
  final double rowH;
  final double? nowDx;
  final VoidCallback onPlay;

  /// Incrémentée par l'écran à chaque lot EPG inséré (import en cours) :
  /// les futures mémorisés se re-arment — sinon un guide ouvert pendant
  /// l'import restait vide jusqu'au prochain décalage de fenêtre.
  final int epgGeneration;
  final bool Function(EpgProgram) canReplay;
  final void Function(EpgProgram) onBlock;

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  /// Requête EPG mémorisée (programme + drapeau « archivable » pré-calculé,
  /// invariant dans le temps) : recréée UNIQUEMENT quand la chaîne, la
  /// fenêtre ou la génération EPG change.
  late Future<List<(EpgProgram, bool)>> _progs;

  @override
  void initState() {
    super.initState();
    _progs = _load();
  }

  @override
  void didUpdateWidget(_GuideRow old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id ||
        old.startMs != widget.startMs ||
        old.endMs != widget.endMs ||
        old.epgGeneration != widget.epgGeneration) {
      _progs = _load();
    }
  }

  Future<List<(EpgProgram, bool)>> _load() => EpgRepository.instance
      .programsBetween(widget.channel.id, widget.startMs, widget.endMs)
      .then((List<EpgProgram> list) =>
          <(EpgProgram, bool)>[for (final EpgProgram p in list) (p, widget.canReplay(p))]);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // ----- Cellule chaîne (focusable) : n° + logo + nom -----
        SizedBox(
          width: widget.chanColW - 8,
          height: widget.rowH,
          child: TvFocusBuilder(
            autofocus: widget.autofocus,
            scale: TvFocusScale.small,
            onSelect: widget.onPlay,
            builder: (BuildContext context, bool focused) {
              // Focus = pill blanc plein (texte noir) façon TiviMate.
              final Color bg = focused ? _tmText : _tmPanel;
              final Color nameColor = focused ? _tmBg : _tmText;
              final Color numColor = focused ? _tmBg : _tmText3;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${widget.number}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: numColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TvChannelLogo(
                        logoUrl: widget.channel.logoUrl,
                        label: widget.channel.name,
                        size: 40,
                        radius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.channel.cleanName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: nameColor),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        // ----- Timeline de la ligne -----
        Expanded(
          child: SizedBox(
            height: widget.rowH,
            child: FutureBuilder<List<(EpgProgram, bool)>>(
              future: _progs,
              builder: (BuildContext context,
                  AsyncSnapshot<List<(EpgProgram, bool)>> snap) {
                final List<(EpgProgram, bool)> progs =
                    snap.data ?? const <(EpgProgram, bool)>[];
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _tmPanel,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    for (final (EpgProgram, bool) e in progs)
                      _block(e.$1, e.$2),
                    if (widget.nowDx != null)
                      Positioned(
                        left: widget.nowDx! - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                            width: 1,
                            color: Colors.white.withValues(alpha: 0.55)),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(EpgProgram p, bool archivable) {
    final double left =
        ((p.startTime - widget.startMs) / 60000).clamp(0, 1e9) * widget.pxPerMin;
    final double right =
        ((widget.endMs - p.stopTime) / 60000).clamp(0, 1e9) * widget.pxPerMin;
    final double windowW =
        (widget.endMs - widget.startMs) / 60000 * widget.pxPerMin;
    final double width =
        (windowW - left - right).clamp(0, windowW).toDouble();
    if (width < 8) return const SizedBox.shrink();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool onAir = p.startTime <= nowMs && nowMs < p.stopTime;
    final bool past = p.stopTime <= nowMs;
    // Garde temporelle évaluée ICI, à chaque build (le tic 30 s repeint) :
    // « archivable » (tuple mémorisé) est invariant, mais une émission à
    // venir ne montre la pastille replay qu'une fois commencée.
    final bool replayable = archivable && (onAir || past);
    return Positioned(
      left: left,
      top: 3,
      bottom: 3,
      width: width - 3,
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: () => widget.onBlock(p),
        builder: (BuildContext context, bool focused) {
          // Focus = pill blanc/texte noir ; en cours = teinté accent ;
          // passé = cellule assombrie ; à venir = #2A2E35.
          final Color bg = focused
              ? _tmText
              : onAir
                  ? const Color(0xFF15304A) // accent très sombre (en cours)
                  : past
                      ? _tmCellPast
                      : _tmCellFuture;
          final Color fg = focused
              ? _tmBg
              : onAir
                  ? _tmAccent
                  : past
                      ? _tmText3
                      : _tmText2;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: onAir && !focused
                  ? Border.all(color: _tmAccent, width: 1)
                  : null,
            ),
            child: Row(
              children: <Widget>[
                if (replayable) ...<Widget>[
                  Icon(Icons.replay_rounded, size: 13, color: fg),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          onAir ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                    ),
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

/// Bouton de décalage du temps (±30 min). Focus = pill blanc.
class _ShiftChip extends StatelessWidget {
  const _ShiftChip({required this.icon, required this.onSelect});
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: 36,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? _tmText : _tmPanel,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 20, color: focused ? _tmBg : _tmText2),
        );
      },
    );
  }
}
