// =========================================================
//  tv_timeline_guide_screen.dart — Guide en GRILLE HORAIRE (style câble US)
// =========================================================
//  La grille classique américaine : chaînes en LIGNES, heures en COLONNES.
//  On voit d'un coup d'œil toute la soirée. Navigation 100 % D-pad :
//    • Haut/Bas   : changer de chaîne (focus sur la cellule de gauche) ;
//    • Gauche/Droite : DÉCALER LA FENÊTRE DE TEMPS de ±30 min (pas de
//      défilement libre : simple et prévisible à la télécommande) ;
//    • OK : regarder la chaîne surlignée.
//
//  PERF (box RAM limitée) :
//    • chaînes paginées (getChannelsPage — même mécanique que le Guide) ;
//    • programmes chargés PAR LIGNE VISIBLE uniquement (FutureBuilder +
//      programsBetween borné à la fenêtre de 3 h, requête SQL indexée) ;
//    • aucun contact avec le lecteur vidéo (on pousse TvPlayerScreen).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/catchup_url_builder.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

class TvTimelineGuideScreen extends StatefulWidget {
  const TvTimelineGuideScreen({super.key});

  @override
  State<TvTimelineGuideScreen> createState() => _TvTimelineGuideScreenState();
}

class _TvTimelineGuideScreenState extends State<TvTimelineGuideScreen> {
  // ----- Géométrie (canevas TV fixe 1280 de large) -----
  static const double _chanColW = 200; // colonne chaînes à gauche
  static const double _pxPerMin = 5.4; // 180 min → 972 px de timeline
  static const int _windowMin = 180; // fenêtre visible : 3 h
  static const double _rowH = 60;
  static const int _kPageSize = 60;

  // ----- Chaînes (paginées, même mécanique que le Guide) -----
  final List<Channel> _channels = <Channel>[];
  int _cursor = 0;
  bool _hasMore = true;
  bool _loading = false;

  // ----- Fenêtre de temps -----
  // Départ arrondi à la demi-heure INFÉRIEURE (comme le câble US), décalable
  // de ±30 min : bornes = [maintenant - 1 h ; maintenant + 24 h].
  late DateTime _windowStart = _floorHalfHour(DateTime.now());
  Timer? _clock; // fait avancer la ligne rouge « maintenant »

  static DateTime _floorHalfHour(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);

  @override
  void initState() {
    super.initState();
    _loadMore();
    // La ligne « maintenant » se met à jour toutes les 30 s (léger).
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
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

  /// Une émission (passée ou en cours) de [channel] est-elle rejouable
  /// (archive du fournisseur dispo) ? Cf. CatchupUrlBuilder.
  bool _canReplay(Channel channel, EpgProgram p) {
    if (p.startDateTime.isAfter(DateTime.now())) return false; // à venir
    return CatchupUrlBuilder.build(channel: channel, program: p) != null;
  }

  /// Action au OK sur une CASE d'émission :
  ///   • en cours  → on regarde la chaîne EN DIRECT ;
  ///   • passée avec archive → on REJOUE depuis le début (catch-up) ;
  ///   • sinon (passée sans archive / à venir) → petit message.
  void _onBlock(int channelIndex, Channel channel, EpgProgram p) {
    final DateTime now = DateTime.now();
    final bool onAir = p.startTime <= now.millisecondsSinceEpoch &&
        now.millisecondsSinceEpoch < p.stopTime;
    if (onAir) {
      _play(channelIndex);
      return;
    }
    final String? url = _canReplay(channel, p)
        ? CatchupUrlBuilder.build(channel: channel, program: p)
        : null;
    if (url != null) {
      // Chaîne SYNTHÉTIQUE (URL d'archive, isLive=false) → LECTEUR EXISTANT.
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
        ? context.l10n.tvProgramUpcoming
        : context.l10n.tvReplayUnavailable);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TvTokens.card,
        content: Text(msg,
            style: TextStyle(color: TvTokens.text, fontSize: TvDimens.body)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int startMs = _windowStart.millisecondsSinceEpoch;
    final int endMs = startMs + _windowMin * 60 * 1000;
    final double timelineW = _windowMin * _pxPerMin;
    // Position de la ligne rouge « maintenant » (si dans la fenêtre).
    final double nowDx =
        (DateTime.now().millisecondsSinceEpoch - startMs) / 60000 * _pxPerMin;
    final bool nowVisible = nowDx >= 0 && nowDx <= timelineW;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ----- En-tête : titre + heures -----
          Row(
            children: <Widget>[
              SizedBox(
                width: _chanColW,
                child: Row(
                  children: <Widget>[
                    Text(
                      context.l10n.tvGuideGridTitle,
                      style: TvTokens.ui(13,
                          weight: FontWeight.w800,
                          color: TvTokens.gold,
                          spacing: 1.6),
                    ),
                    const Spacer(),
                    // Décalage du temps par BOUTONS visibles (les flèches sont
                    // désormais libres pour naviguer entre les cases).
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
                            _labelAt(_windowStart
                                .add(Duration(minutes: m))),
                            style: TvTokens.ui(12,
                                weight: FontWeight.w700,
                                color: TvTokens.muted),
                          ),
                        ),
                      if (nowVisible)
                        Positioned(
                          left: nowDx - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: TvTokens.live),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.tvGuideGridHint,
              style: TvTokens.ui(12, color: TvTokens.mutedDim),
            ),
          ),
          // ----- Lignes chaînes -----
          Expanded(
            child: _channels.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    addAutomaticKeepAlives: false,
                    itemExtent: _rowH + 6,
                    itemCount: _channels.length,
                    itemBuilder: (BuildContext context, int i) {
                      // Pagination : on précharge en approchant de la fin.
                      if (i >= _channels.length - 12) _loadMore();
                      final int idx = i;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _GuideRow(
                          channel: _channels[i],
                          autofocus: i == 0,
                          startMs: startMs,
                          endMs: endMs,
                          pxPerMin: _pxPerMin,
                          chanColW: _chanColW,
                          rowH: _rowH,
                          nowDx: nowVisible ? nowDx : null,
                          onPlay: () => _play(idx),
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
    );
  }

  String _labelAt(DateTime t) {
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Une LIGNE de la grille : cellule chaîne (focusable, OK = direct) +
/// blocs de programmes DÉSORMAIS FOCUSABLES (OK = direct / ⟲ revoir).
///
/// FLUIDITÉ — StatefulWidget avec FUTURE MÉMORISÉ : avant, le
/// FutureBuilder recréait sa requête `programsBetween` à CHAQUE build.
/// Or l'écran entier se reconstruit toutes les 30 s (tic de la ligne
/// « maintenant ») et à chaque décalage de fenêtre → chaque tic
/// relançait une requête SQLite PAR LIGNE VISIBLE alors que la fenêtre
/// n'avait pas bougé. Le future ne se recrée désormais que si la
/// chaîne OU la fenêtre temporelle change (didUpdateWidget).
class _GuideRow extends StatefulWidget {
  const _GuideRow({
    required this.channel,
    required this.autofocus,
    required this.startMs,
    required this.endMs,
    required this.pxPerMin,
    required this.chanColW,
    required this.rowH,
    required this.nowDx,
    required this.onPlay,
    required this.canReplay,
    required this.onBlock,
  });

  final Channel channel;
  final bool autofocus;
  final int startMs;
  final int endMs;
  final double pxPerMin;
  final double chanColW;
  final double rowH;
  final double? nowDx;
  final VoidCallback onPlay;

  /// Une émission est-elle rejouable (archive dispo) ? → pastille ⟲.
  final bool Function(EpgProgram) canReplay;

  /// OK sur une case d'émission.
  final void Function(EpgProgram) onBlock;

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  /// Requête EPG mémorisée (programme + drapeau « rejouable » PRÉ-CALCULÉ :
  /// la construction d'URL catch-up de canReplay ne se refait plus à chaque
  /// rebuild de bloc) : recréée UNIQUEMENT quand la chaîne ou la fenêtre
  /// change — jamais sur un simple tic d'horloge de l'écran.
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
        old.endMs != widget.endMs) {
      _progs = _load();
    }
  }

  Future<List<(EpgProgram, bool)>> _load() => EpgRepository.instance
      .programsBetween(widget.channel.id, widget.startMs, widget.endMs)
      .then((List<EpgProgram> list) => <(EpgProgram, bool)>[
            for (final EpgProgram p in list) (p, widget.canReplay(p))
          ]);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // ----- Cellule chaîne (focusable) -----
        SizedBox(
          width: widget.chanColW - 8,
          height: widget.rowH,
          child: TvFocusBuilder(
            autofocus: widget.autofocus,
            scale: TvFocusScale.small,
            onSelect: widget.onPlay,
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.card;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.text;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TvTokens.lineSoft),
                ),
                child: Text(
                  widget.channel.cleanName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: fg),
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
              // Borné à la fenêtre : requête SQL indexée, par ligne
              // visible — et MÉMORISÉE (cf. _GuideRowState : le tic
              // 30 s de l'écran ne re-tape plus SQLite).
              future: _progs,
              builder: (BuildContext context,
                  AsyncSnapshot<List<(EpgProgram, bool)>> snap) {
                final List<(EpgProgram, bool)> progs =
                    snap.data ?? const <(EpgProgram, bool)>[];
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: <Widget>[
                    // Fond de piste (hachure discrète = pas de données).
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: TvTokens.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: TvTokens.lineSoft),
                        ),
                      ),
                    ),
                    for (final (EpgProgram, bool) e in progs)
                      _block(e.$1, e.$2),
                    if (widget.nowDx != null)
                      Positioned(
                        left: widget.nowDx! - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(
                            width: 2,
                            color: TvTokens.live.withValues(alpha: 0.55)),
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

  Widget _block(EpgProgram p, bool replayable) {
    // Position/longueur du bloc, ROGNÉES à la fenêtre visible.
    final double left =
        ((p.startTime - widget.startMs) / 60000).clamp(0, 1e9) * widget.pxPerMin;
    final double right =
        ((widget.endMs - p.stopTime) / 60000).clamp(0, 1e9) * widget.pxPerMin;
    final double windowW = (widget.endMs - widget.startMs) / 60000 * widget.pxPerMin;
    final double width =
        (windowW - left - right).clamp(0, windowW).toDouble();
    if (width < 8) return const SizedBox.shrink();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool onAir = p.startTime <= nowMs && nowMs < p.stopTime;
    return Positioned(
      left: left,
      top: 3,
      bottom: 3,
      width: width - 3, // petit interstice entre blocs
      // Case FOCUSABLE : OK = regarder (en direct) / ⟲ revoir (passé + archive).
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: () => widget.onBlock(p),
        builder: (BuildContext context, bool focused) {
          final Color bg = focused
              ? TvTokens.gold
              : (onAir ? TvTokens.badgeBg : TvTokens.sel);
          final Color fg = focused
              ? const Color(0xFF1A1206)
              : (onAir ? TvTokens.goldBright : TvTokens.text);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: focused
                      ? TvTokens.gold
                      : (onAir ? TvTokens.gold : TvTokens.lineSoft),
                  width: focused ? 2 : 1),
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
                      fontWeight: onAir ? FontWeight.w700 : FontWeight.w600,
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

/// Petit bouton de décalage du temps (±30 min) dans l'en-tête de la grille.
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
          width: 34,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rSmall),
            border: Border.all(color: TvTokens.lineSoft),
          ),
          child: Icon(icon,
              size: 20,
              color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright),
        );
      },
    );
  }
}
