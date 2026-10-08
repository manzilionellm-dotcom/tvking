// Scores et calendriers publics, ouverts seulement sur demande depuis Sport.
// Le rafraîchissement communautaire s'arrête hors de cet écran et après une
// panne. Un échec reste visible jusqu'au choix explicite « Réessayer ».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../sports/data/football_feed_repository.dart';
import '../../sports/domain/football_feed.dart';
import 'tv_sports_status.dart';

class TvFootballScoresScreen extends StatefulWidget {
  const TvFootballScoresScreen({super.key});
  @override
  State<TvFootballScoresScreen> createState() => _TvFootballScoresScreenState();
}

class _TvFootballScoresScreenState extends State<TvFootballScoresScreen> {
  final FootballFeedRepository _repository = FootballFeedRepository();
  FootballCompetition _competition = FootballCompetition.bundesliga;
  FootballFeedResult _result = const FootballFeedResult();
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _loading || _result.failure != null || _result.disabled) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      // OpenFootball est un calendrier différé : le recharger chaque minute
      // ne ferait pas apparaître des résultats en direct.
      if (_competition.source == FootballSource.openLigaDb) unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (_loading) return;
    final FootballCompetition requested = _competition;
    setState(() => _loading = true);
    final FootballFeedResult result = await _repository.load(requested);
    if (!mounted || requested != _competition) return;
    setState(() {
      _loading = false;
      // Une panne ne transforme pas les scores déjà reçus en liste vide.
      _result = result.failure == null ? result : FootballFeedResult(
          matches: _result.matches, receivedAt: _result.receivedAt,
          failure: result.failure);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool community = _competition.source == FootballSource.openLigaDb;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    bool upcoming(FootballMatch m) => !m.finished &&
        !m.startsAt.isBefore(community ? now : today);
    final List<FootballMatch> past = _result.matches
        .where((FootballMatch m) => !upcoming(m)).toList().reversed.take(24).toList();
    final List<FootballMatch> next = _result.matches
        .where(upcoming).take(24).toList();
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        IconButton(onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary)),
        Expanded(child: Text(context.l10n.sportsFootballTitle, style: AppTextStyles.headlineLarge)),
        TextButton(onPressed: _loading ? null : _reload,
            child: Text(context.l10n.sportsRefresh, style: AppTextStyles.button)),
      ]),
      DropdownButton<FootballCompetition>(
        value: _competition, isExpanded: true, dropdownColor: AppColors.surface,
        style: AppTextStyles.headlineMedium,
        items: FootballCompetition.values.map((FootballCompetition c) =>
          DropdownMenuItem<FootballCompetition>(value: c, child: Text(c.label))).toList(),
        onChanged: _loading ? null : (FootballCompetition? c) {
          if (c == null || c == _competition) return;
          setState(() { _competition = c; _result = const FootballFeedResult(); });
          unawaited(_reload());
        },
      ),
      Text(community ? context.l10n.sportsCommunityNotice : context.l10n.sportsCalendarNotice,
          style: AppTextStyles.bodyLarge),
      if (_result.receivedAt != null)
        Text(context.l10n.sportsRetrievedAt(DateFormat.Hm(locale).format(_result.receivedAt!.toLocal())),
            style: AppTextStyles.bodyMedium),
      if (_loading || _result.failure != null)
        TvSportsStatus(loading: _loading, failure: _result.failure, onRetry: _reload),
      const SizedBox(height: 12),
      Expanded(child: ListView(children: <Widget>[
        if (!_loading && _result.failure == null && _result.matches.isEmpty)
          Text(context.l10n.tvNoData, style: AppTextStyles.headlineMedium),
        if (next.isNotEmpty) Text(context.l10n.sportsUpcoming, style: AppTextStyles.headlineMedium),
        for (final FootballMatch match in next) _FootballTile(match: match, community: community),
        if (past.isNotEmpty) Text(context.l10n.sportsRecent, style: AppTextStyles.headlineMedium),
        for (final FootballMatch match in past) _FootballTile(match: match, community: community),
        // Attribution des données, lisible sur la télé (ODbL / CC0).
        Text(community ? 'Données : OpenLigaDB · openligadb.de/lizenz · ODbL 1.0'
            : 'Données : OpenFootball · github.com/openfootball/football.json · CC0',
            style: AppTextStyles.bodyMedium),
      ])),
    ]);
  }
}

class _FootballTile extends StatelessWidget {
  const _FootballTile({required this.match, required this.community});
  final FootballMatch match;
  final bool community;
  @override
  Widget build(BuildContext context) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime date = community ? match.startsAt.toLocal() : match.startsAt;
    final String when = community ? DateFormat.yMMMd(locale).add_Hm().format(date)
        : DateFormat.yMMMd(locale).format(date);
    return Card(color: AppColors.surface, child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('${match.home}  ${match.hasScore ? '${match.homeScore} – ${match.awayScore}' : '–'}  ${match.away}',
            style: AppTextStyles.headlineMedium),
        Text('$when${match.finished ? ' · ${context.l10n.sportsFinished}' : ''}',
            style: AppTextStyles.bodyMedium),
        for (final FootballGoal goal in match.goals)
          Text('${goal.minute == null ? '' : '${goal.minute}′ · '}${goal.home} – ${goal.away}${goal.player.isEmpty ? '' : ' · ${goal.player}'}',
              style: AppTextStyles.bodyLarge),
      ]),
    ));
  }
}
