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
import 'package:flutter/services.dart';

import '../../channels/domain/channel.dart';
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

  // Gauche/Droite = décaler le temps (capturé AVANT le déplacement de focus).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _shiftWindow(-30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _shiftWindow(30);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

    return Focus(
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ----- En-tête : titre + heures -----
          Row(
            children: <Widget>[
              SizedBox(
                width: _chanColW,
                child: Text(
                  'GRILLE TV',
                  style: TvTokens.ui(13,
                      weight: FontWeight.w800,
                      color: TvTokens.gold,
                      spacing: 1.6),
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
              '◀ ▶ : avancer/reculer de 30 min   ·   OK : regarder',
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
                          onPlay: () => _play(i),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _labelAt(DateTime t) {
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Une LIGNE de la grille : cellule chaîne (focusable, OK = lecture) +
/// blocs de programmes positionnés sur la timeline (affichage seul).
class _GuideRow extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // ----- Cellule chaîne (focusable) -----
        SizedBox(
          width: chanColW - 8,
          height: rowH,
          child: TvFocusBuilder(
            autofocus: autofocus,
            scale: TvFocusScale.small,
            onSelect: onPlay,
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
                  channel.cleanName,
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
            height: rowH,
            child: FutureBuilder<List<EpgProgram>>(
              // Borné à la fenêtre : requête SQL indexée, par ligne visible.
              future: EpgRepository.instance
                  .programsBetween(channel.id, startMs, endMs),
              builder: (BuildContext context,
                  AsyncSnapshot<List<EpgProgram>> snap) {
                final List<EpgProgram> progs =
                    snap.data ?? const <EpgProgram>[];
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
                    for (final EpgProgram p in progs) _block(p),
                    if (nowDx != null)
                      Positioned(
                        left: nowDx! - 1,
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

  Widget _block(EpgProgram p) {
    // Position/longueur du bloc, ROGNÉES à la fenêtre visible.
    final double left =
        ((p.startTime - startMs) / 60000).clamp(0, 1e9) * pxPerMin;
    final double right =
        ((endMs - p.stopTime) / 60000).clamp(0, 1e9) * pxPerMin;
    final double windowW = (endMs - startMs) / 60000 * pxPerMin;
    final double width =
        (windowW - left - right).clamp(0, windowW).toDouble();
    if (width < 8) return const SizedBox.shrink();
    final bool onAir = p.startTime <=
            DateTime.now().millisecondsSinceEpoch &&
        DateTime.now().millisecondsSinceEpoch < p.stopTime;
    return Positioned(
      left: left,
      top: 3,
      bottom: 3,
      width: width - 3, // petit interstice entre blocs
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: onAir ? TvTokens.badgeBg : TvTokens.sel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: onAir ? TvTokens.gold : TvTokens.lineSoft),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            p.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: onAir ? FontWeight.w700 : FontWeight.w600,
              color: onAir ? TvTokens.goldBright : TvTokens.text,
            ),
          ),
        ),
      ),
    );
  }
}
