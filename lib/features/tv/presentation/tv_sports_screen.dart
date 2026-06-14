// =========================================================
//  tv_sports_screen.dart — « Actu » sport + équipe préférée (10-foot)
// =========================================================
//  Bandeau défilant des matchs (résultats + à venir), rafraîchi toutes les
//  10 min. Le client choisit SON équipe → on affiche son dernier match (score)
//  et son prochain match. Données = TheSportsDB via le Worker (proxy + cache).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

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
  StreamSubscription<SportTeam?>? _favSub;
  StreamSubscription<SportsEvents>? _evSub;
  SportTeam? _fav = SportsRepository.instance.favorite;
  SportsEvents _events = SportsRepository.instance.events;

  @override
  void initState() {
    super.initState();
    SportsRepository.instance.initialize();
    _favSub = SportsRepository.instance.favoriteStream.listen((SportTeam? t) {
      if (mounted) setState(() => _fav = t);
    });
    _evSub = SportsRepository.instance.eventsStream.listen((SportsEvents e) {
      if (mounted) setState(() => _events = e);
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _evSub?.cancel();
    super.dispose();
  }

  Future<void> _pickTeam() async {
    final SportTeam? t = await Navigator.of(context).push<SportTeam>(
      MaterialPageRoute<SportTeam>(
        builder: (_) => const TvShell(child: TvTeamPickerScreen()),
      ),
    );
    if (t != null) await SportsRepository.instance.setFavorite(t);
  }

  @override
  Widget build(BuildContext context) {
    final SportTeam? fav = _fav;
    if (fav == null) return _emptyState();

    final List<String> tickerItems = <String>[
      ..._events.last.map((SportEvent e) => e.ticker),
      ..._events.next.map((SportEvent e) => e.ticker),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ----- Bandeau défilant -----
        if (tickerItems.isNotEmpty) _Ticker(items: tickerItems),
        if (tickerItems.isNotEmpty) const SizedBox(height: 18),
        // ----- En-tête équipe -----
        Row(
          children: <Widget>[
            _badge(fav.badge, 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(fav.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.displayS,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.text)),
                  if (fav.league.isNotEmpty)
                    Text(fav.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: TvDimens.label, color: TvTokens.muted)),
                ],
              ),
            ),
            _PillButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Changer',
                onSelect: _pickTeam),
          ],
        ),
        const SizedBox(height: 18),
        // ----- Dernier / Prochain match -----
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _MatchCard(
                  title: 'Dernier match',
                  event: _events.last.isNotEmpty ? _events.last.first : null,
                ),
              ),
              const SizedBox(width: TvDimens.gutter),
              Expanded(
                child: _MatchCard(
                  title: 'Prochain match',
                  event: _events.next.isNotEmpty ? _events.next.first : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.sports_soccer_rounded,
                size: 64, color: TvTokens.mutedDim),
            const SizedBox(height: 16),
            Text('Choisis ton équipe préférée',
                style: TvTokens.display(32, color: TvTokens.text)),
            const SizedBox(height: 8),
            SizedBox(
              width: 520,
              child: Text(
                'Tu verras son dernier résultat et son prochain match (avec le score), '
                'plus un bandeau d\'actu sport qui défile, mis à jour toutes les 10 minutes.',
                textAlign: TextAlign.center,
                style: TvTokens.ui(16, color: TvTokens.mutedDim),
              ),
            ),
            const SizedBox(height: 22),
            _PillButton(
                icon: Icons.add_rounded,
                label: 'Choisir mon équipe',
                autofocus: true,
                onSelect: _pickTeam),
          ],
        ),
      );

  Widget _badge(String url, double size) => SizedBox(
        width: size,
        height: size,
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.contain,
                cacheWidth: 160,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.shield_rounded, color: TvTokens.muted))
            : const Icon(Icons.shield_rounded, color: TvTokens.muted),
      );
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title.toUpperCase(),
              style: TvTokens.ui(13,
                  weight: FontWeight.w700, color: TvTokens.mutedDim, spacing: 1.5)),
          const SizedBox(height: 14),
          if (event == null)
            Text('Aucune donnée pour le moment',
                style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim))
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(event!.home,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      event!.hasScore
                          ? '${event!.homeScore} – ${event!.awayScore}'
                          : 'vs',
                      style: TextStyle(
                          fontSize: event!.hasScore ? 34 : 22,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.goldBright)),
                ),
                Expanded(
                  child: Text(event!.away,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              style: TextStyle(fontSize: TvDimens.label, color: TvTokens.muted),
            ),
          ],
        ],
      ),
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
