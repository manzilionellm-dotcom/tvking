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

import '../../../core/i18n/l10n_extension.dart';

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
                icon: Icons.add_rounded, label: 'Ajouter', onSelect: _addTeam),
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
                'Tu verras leurs scores et leurs prochains matchs, un bandeau d\'actu '
                'qui défile, et une alarme ~1 h avant chaque match.',
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
                    title: 'Dernier match',
                    event: events.last.isNotEmpty ? events.last.first : null),
              ),
              const SizedBox(width: TvDimens.gutter),
              Expanded(
                child: _MatchCard(
                    title: 'Prochain match',
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

class _TickerState extends State<_Ticker> {
  final ScrollController _sc = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_sc.hasClients) return;
      final double max = _sc.position.maxScrollExtent;
      if (max <= 0) return;
      double next = _sc.offset + 1.2;
      if (next >= max) next = 0;
      _sc.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
            child: const Text('ACTU',
                style: TextStyle(
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
                          : 'vs',
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
          ],
        ],
      ),
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
