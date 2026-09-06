// =========================================================
//  tv_sports_screen.dart — « Actu » sport + équipes préférées (10-foot)
// =========================================================
//  Plusieurs équipes préférées. Pour chacune : dernier match (score) + prochain
//  match, + un bandeau ACTU qui défile (tous les matchs). Rafraîchi 10 min. Une
//  ALARME est posée ~1 h avant chaque match à venir. Données = TheSportsDB via
//  le Worker (proxy + cache).
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/i18n/l10n_extension.dart';

import '../../sports/data/predictions_service.dart';
import '../../sports/data/sports_repository.dart';
import '../../sports/domain/sport_models.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';
import 'tv_team_picker_screen.dart';

class TvSportsScreen extends StatefulWidget {
  const TvSportsScreen({super.key});

  @override
  State<TvSportsScreen> createState() => _TvSportsScreenState();
}

class _TvSportsScreenState extends State<TvSportsScreen> {
  StreamSubscription<List<SportTeam>>? _favSub;
  StreamSubscription<void>? _changeSub;
  List<SportTeam> _favs = SportsRepository.instance.favorites;

  @override
  void initState() {
    super.initState();
    SportsRepository.instance.initialize();
    _favSub = SportsRepository.instance.favoritesStream.listen((List<SportTeam> t) {
      if (mounted) setState(() => _favs = t);
    });
    _changeSub = SportsRepository.instance.changesStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _changeSub?.cancel();
    super.dispose();
  }

  Future<void> _addTeam() async {
    final SportTeam? t = await Navigator.of(context).push<SportTeam>(
      MaterialPageRoute<SportTeam>(
        builder: (_) => const TvShell(child: TvTeamPickerScreen()),
      ),
    );
    if (t != null) await SportsRepository.instance.addFavorite(t);
  }

  @override
  Widget build(BuildContext context) {
    if (_favs.isEmpty) return _emptyState();

    final List<String> tickerItems = <String>[];
    for (final SportTeam t in _favs) {
      final SportsEvents e = SportsRepository.instance.eventsFor(t.id);
      tickerItems.addAll(e.last.map((SportEvent x) => x.ticker));
      tickerItems.addAll(e.next.map((SportEvent x) => x.ticker));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (tickerItems.isNotEmpty) _Ticker(items: tickerItems),
        if (tickerItems.isNotEmpty) const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Text(context.l10n.tvMyTeams,
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const Spacer(),
            _PillButton(
                icon: Icons.add_rounded,
                label: context.l10n.buttonAdd,
                onSelect: _addTeam),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            itemCount: _favs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int i) {
              final SportTeam t = _favs[i];
              return _TeamSection(
                team: t,
                events: SportsRepository.instance.eventsFor(t.id),
                autofocus: i == 0,
                onRemove: () => SportsRepository.instance.removeFavorite(t.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.sports_soccer_rounded, size: 64, color: TvTokens.mutedDim),
            const SizedBox(height: 16),
            Text(context.l10n.tvChooseTeams,
                style: TvTokens.display(32, color: TvTokens.text)),
            const SizedBox(height: 8),
            SizedBox(
              width: 560,
              child: Text(
                context.l10n.tvSportPickIntro,
                textAlign: TextAlign.center,
                style: TvTokens.ui(16, color: TvTokens.mutedDim),
              ),
            ),
            const SizedBox(height: 22),
            _PillButton(
                icon: Icons.add_rounded,
                label: context.l10n.tvChooseMyTeam,
                autofocus: true,
                onSelect: _addTeam),
          ],
        ),
      );
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.team,
    required this.events,
    required this.onRemove,
    this.autofocus = false,
  });
  final SportTeam team;
  final SportsEvents events;
  final VoidCallback onRemove;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TvTokens.panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                height: 44,
                child: team.badge.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: team.badge,
                        fit: BoxFit.contain,
                        memCacheWidth: 120,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) =>
                            const Icon(Icons.shield_rounded, color: TvTokens.muted),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.shield_rounded, color: TvTokens.muted))
                    : const Icon(Icons.shield_rounded, color: TvTokens.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
              ),
              _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  autofocus: autofocus,
                  onSelect: onRemove),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _MatchCard(
                    title: context.l10n.tvSportLastMatch,
                    event: events.last.isNotEmpty ? events.last.first : null),
              ),
              const SizedBox(width: TvDimens.gutter),
              Expanded(
                child: _MatchCard(
                    title: context.l10n.tvSportNextMatch,
                    event: events.next.isNotEmpty ? events.next.first : null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bandeau qui défile horizontalement (résultats + matchs à venir).
class _Ticker extends StatefulWidget {
  const _Ticker({required this.items});
  final List<String> items;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker>
    with SingleTickerProviderStateMixin {
  final ScrollController _sc = ScrollController();

  // TICKER (vsync) et non Timer.periodic(30 ms) : l'ancien timer poussait
  // un jumpTo à ~33 Hz DÉSYNCHRONISÉ du rafraîchissement (layout+paint
  // permanents, à contretemps des frames) — et continuait de tourner sous
  // un écran poussé par-dessus. Un Ticker est cadencé par le vsync ET
  // silencé automatiquement par TickerMode quand l'écran est recouvert.
  late final Ticker _ticker = createTicker(_onTick);
  Duration _prev = Duration.zero;
  static const double _pxPerSecond = 40; // ≈ l'ancien 1,2 px / 30 ms

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // Clamp : elapsed continue de compter pendant le mute TickerMode (écran
    // recouvert) — sans borne, le 1er tick au retour faisait sauter le
    // bandeau de toute la durée d'absence.
    final double dt =
        ((elapsed - _prev).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _prev = elapsed;
    if (!_sc.hasClients) return;
    final double max = _sc.position.maxScrollExtent;
    if (max <= 0) return;
    double next = _sc.offset + _pxPerSecond * dt;
    if (next >= max) next = 0;
    _sc.jumpTo(next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TvTokens.live,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(TvDimens.cardRadius),
                bottomLeft: Radius.circular(TvDimens.cardRadius),
              ),
            ),
            child: Text(context.l10n.tvSportNews,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white)),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _sc,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  for (final String it in widget.items) ...<Widget>[
                    Text(it,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: TvTokens.text)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('•', style: TextStyle(color: TvTokens.gold)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.title, required this.event});
  final String title;
  final SportEvent? event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title.toUpperCase(),
              style: TvTokens.ui(12,
                  weight: FontWeight.w700, color: TvTokens.mutedDim, spacing: 1.2)),
          const SizedBox(height: 12),
          if (event == null)
            Text(context.l10n.tvNoData,
                style: TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim))
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(event!.home,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: TvDimens.titleS,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                      event!.hasScore
                          ? '${event!.homeScore} – ${event!.awayScore}'
                          : context.l10n.tvSportVersus,
                      style: TextStyle(
                          fontSize: event!.hasScore ? 28 : 18,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.goldBright)),
                ),
                Expanded(
                  child: Text(event!.away,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.titleS,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              <String>[
                if (event!.league.isNotEmpty) event!.league,
                if (event!.hasScore && event!.status.isNotEmpty)
                  event!.status
                else if (event!.whenLabel.isNotEmpty)
                  event!.whenLabel,
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: TvDimens.caption, color: TvTokens.muted),
            ),
            // PRONOSTIC DES FANS (06/09) — à la télécommande : trois boutons
            // focusables « 1 / N / 2 ». Ne rend rien pour un match joué
            // sans vote ni pourcentages.
            _TvPredictionRow(event: event!),
          ],
        ],
      ),
    );
  }
}

/// « 1 · N · 2 » façon 10-foot : trois boutons D-pad, pourcentages des
/// fans après le vote, figé au coup d'envoi. Même service que le
/// téléphone (PredictionsService) : un vote posé sur la box se retrouve
/// sur le téléphone du même client, et inversement, par le serveur.
class _TvPredictionRow extends StatefulWidget {
  const _TvPredictionRow({required this.event});
  final SportEvent event;

  @override
  State<_TvPredictionRow> createState() => _TvPredictionRowState();
}

class _TvPredictionRowState extends State<_TvPredictionRow> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PredictionsService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (widget.event.isDuel) {
      unawaited(PredictionsService.instance.load(widget.event.id));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SportEvent e = widget.event;
    if (!e.isDuel) return const SizedBox.shrink();
    final PredictionsService svc = PredictionsService.instance;
    final bool open = PredictionsService.isOpen(e, DateTime.now());
    final PredictionTally? tally = svc.tallyFor(e.id);
    final Pick? mine = tally?.mine ?? svc.myPick(e.id);
    if (!open && mine == null && (tally == null || tally.total == 0)) {
      return const SizedBox.shrink();
    }
    final bool showPct =
        tally != null && tally.total > 0 && (mine != null || !open);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: <Widget>[
          Text(
            open
                ? context.l10n.sportPredictTitle
                : context.l10n.sportPredictClosed,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim),
          ),
          const SizedBox(width: 12),
          for (final Pick p in Pick.values) ...<Widget>[
            _TvPickButton(
              label: p == Pick.draw
                  ? context.l10n.sportPredictDraw
                  : (p == Pick.home ? '1' : '2'),
              pct: showPct ? tally.pct(p) : null,
              selected: mine == p,
              enabled: open,
              onSelect: () => unawaited(svc.vote(e, p)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TvPickButton extends StatelessWidget {
  const _TvPickButton({
    required this.label,
    required this.pct,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });
  final String label;
  final int? pct;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final String text = pct == null ? label : '$label · $pct %';
    if (!enabled) {
      // Fermé : lisible, mais hors du parcours D-pad (rien à faire dessus).
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? TvTokens.sel : Colors.transparent,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(
              color: selected ? TvTokens.gold : TvTokens.lineSoft),
        ),
        child: Text(text,
            style: TvTokens.ui(TvDimens.caption,
                weight: FontWeight.w700,
                color: selected ? TvTokens.goldBright : TvTokens.muted)),
      );
    }
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (selected ? TvTokens.goldBright : TvTokens.text);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : (selected ? TvTokens.sel : TvTokens.card),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
                color: selected || focused ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Text(text,
              style: TvTokens.ui(TvDimens.caption,
                  weight: FontWeight.w700, color: fg)),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onSelect, this.autofocus = false});
  final IconData icon;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 24, color: focused ? const Color(0xFF1A1206) : TvTokens.muted),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton(
      {required this.icon,
      required this.label,
      required this.onSelect,
      this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 9),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}
