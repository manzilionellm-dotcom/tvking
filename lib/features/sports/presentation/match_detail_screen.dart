// =========================================================
//  match_detail_screen.dart — La FICHE d'un match (téléphone)
// =========================================================
//  Demande du propriétaire (07/09/2026) : « au clic sur une carte, ouvre
//  une vue détaillée : lecteur vidéo en haut, puis des onglets
//  horizontaux — Résumé, Stats, Compositions, Corners, Cartons, xG,
//  Heatmap. Les corners et stats sont cliquables et s'expansent au
//  toucher, comme SofaScore. »
//
//  LE « LECTEUR EN HAUT », honnêtement : cette app ne possède aucun flux.
//  Elle ne peut montrer QUE ce que la liste du client diffuse. On cherche
//  donc, dans le guide (EPG) des chaînes du client, une émission EN COURS
//  dont le titre contient le nom d'une des deux équipes. Trouvée → une
//  grande tuile « Regarder sur <chaîne> » ouvre le lecteur. Pas trouvée
//  → on le dit, sans écran noir qui ferait croire à une panne.
//
//  xG ET HEATMAP : la source (TheSportsDB) ne les fournit pas. Les deux
//  onglets existent, comme demandé, et disent « non fourni par la
//  source ». On n'invente pas un chiffre.
//
//  Couleurs et tailles : AppColors / AppTextStyles uniquement.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../player/presentation/play_channel.dart';
import '../data/live_scores_service.dart';
import '../data/match_channel_finder.dart';
import '../data/match_detail_service.dart';
import '../domain/match_detail.dart';
import '../domain/sport_models.dart';
import 'prediction_bar.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({super.key, required this.event});
  final SportEvent event;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);
  MatchDetail? _detail;
  bool _loading = true;
  Channel? _channel;
  bool _channelSearched = false;
  StreamSubscription<void>? _liveSub;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_findChannel());
    // Les scores en direct font vivre l'en-tête pendant qu'on lit la fiche.
    LiveScoresService.instance.start();
    _liveSub = LiveScoresService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // La fiche elle-même (stats, chronologie) bouge pendant un match :
    // on la relit à la cadence du cache serveur (60 s).
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_live) unawaited(_load(force: true));
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _refresh?.cancel();
    LiveScoresService.instance.stop();
    _tabs.dispose();
    super.dispose();
  }

  SportEvent get _event => LiveScoresService.instance.enrich(widget.event);
  bool get _live =>
      LiveScoresService.instance.forId(widget.event.id) != null &&
      _event.isLive;

  Future<void> _load({bool force = false}) async {
    final MatchDetail? d =
        await MatchDetailService.instance.load(widget.event.id, force: force);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
    });
  }

  /// Cherche dans le guide du client une chaîne qui diffuse ce match.
  ///
  //  LE CALCUL A DÉMÉNAGÉ (07/09/2026) dans
  //  `data/match_channel_finder.dart`, partagé avec les CARTES de la
  //  liste. Deux implémentations auraient fini par se contredire : le
  //  client aurait lu une chaîne sur la liste et une autre — ou aucune —
  //  en ouvrant la fiche.
  //
  //  Au passage, le vrai défaut est corrigé : on cherchait « ce qui
  //  passe MAINTENANT ». Pour un match à 22 h consulté à 21 h 30, la
  //  réponse était forcément « aucune chaîne » — à cet instant la chaîne
  //  diffusait encore autre chose. Le module interroge le guide à
  //  l'heure du coup d'envoi.
  Future<void> _findChannel() async {
    final Channel? ch = await MatchChannelFinder.instance.find(widget.event);
    if (!mounted) return;
    setState(() {
      _channel = ch;
      _channelSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SportEvent e = _event;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          e.league.isNotEmpty ? e.league : e.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: <Widget>[
          _videoZone(e),
          _scoreBlock(e),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PredictionBar(event: e),
          ),
          const SizedBox(height: 6),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.accent,
            labelStyle: AppTextStyles.labelSmall.copyWith(fontSize: 12),
            tabs: <Widget>[
              Tab(text: context.l10n.sportDetailSummary),
              Tab(text: context.l10n.sportDetailStats),
              Tab(text: context.l10n.sportDetailLineups),
              Tab(text: context.l10n.sportDetailCorners),
              Tab(text: context.l10n.sportDetailCards),
              Tab(text: context.l10n.sportDetailXg),
              Tab(text: context.l10n.sportDetailHeatmap),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: <Widget>[
                      _summaryTab(),
                      _statsTab(),
                      _lineupsTab(),
                      _cornersTab(),
                      _cardsTab(),
                      _notProvided(),
                      _notProvided(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  //  En-tête : la zone vidéo, puis le score
  // ---------------------------------------------------------------

  Widget _videoZone(SportEvent e) {
    final Channel? ch = _channel;
    final String? thumb =
        _detail?.thumb.isNotEmpty == true ? _detail!.thumb : null;
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: ch == null ? null : () => unawaited(playChannel(context, ch)),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (thumb != null)
                Image.network(
                  thumb,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              // Voile sombre : le texte reste lisible sur n'importe quelle
              // vignette, et une vignette absente donne un fond uni propre.
              Container(color: AppColors.background.withValues(alpha: 0.55)),
              Center(
                child: ch != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.play_circle_fill_rounded,
                              size: 52, color: AppColors.accent),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.sportWatchOn(ch.cleanName),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _channelSearched
                              ? context.l10n.sportNoChannelAiring
                              : '',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBlock(SportEvent e) {
    final bool live = _live;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: <Widget>[
          Expanded(child: _side(e.homeBadge, e.home)),
          Column(
            children: <Widget>[
              Text(
                e.hasScore ? '${e.homeScore} – ${e.awayScore}' : '–',
                style: AppTextStyles.headlineLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: live ? AppColors.live : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              if (live)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const LiveBadge(),
                    const SizedBox(width: 6),
                    BlinkingText(
                      e.liveLabel,
                      style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.live, fontWeight: FontWeight.w800),
                    ),
                  ],
                )
              else
                Text(
                  e.hasScore && e.status.isNotEmpty ? e.status : e.whenLabel,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
            ],
          ),
          Expanded(child: _side(e.awayBadge, e.away)),
        ],
      ),
    );
  }

  Widget _side(String badge, String name) => Column(
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: badge.isEmpty
                ? const Icon(Icons.shield_rounded, color: AppColors.textMuted)
                : Image.network(badge,
                    cacheWidth: 132,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.shield_rounded,
                        color: AppColors.textMuted)),
          ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall
                  .copyWith(fontWeight: FontWeight.w700)),
        ],
      );

  // ---------------------------------------------------------------
  //  Onglets
  // ---------------------------------------------------------------

  Widget _noData() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.sportDetailNoData,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textTertiary)),
        ),
      );

  Widget _notProvided() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.textMuted, size: 32),
              const SizedBox(height: 10),
              Text(context.l10n.sportDetailNotProvided,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
      );

  Widget _summaryTab() {
    final MatchDetail? d = _detail;
    if (d == null ||
        (d.summary.isEmpty && d.goals.isEmpty && d.venue.isEmpty)) {
      return _noData();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        if (d.venue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: <Widget>[
              const Icon(Icons.stadium_outlined,
                  size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(d.venue,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textTertiary)),
              ),
            ]),
          ),
        for (final MatchIncident g in d.goals) _incidentRow(g),
        if (d.summary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(d.summary, style: AppTextStyles.bodyMedium),
        ],
      ],
    );
  }

  Widget _incidentRow(MatchIncident i) {
    final IconData icon = i.isGoal
        ? Icons.sports_soccer_rounded
        : (i.isCard ? Icons.square_rounded : Icons.circle_outlined);
    final Color color = i.isRedCard
        ? AppColors.live
        : (i.isYellowCard ? AppColors.warning : AppColors.textSecondary);
    final Widget text = Column(
      crossAxisAlignment:
          i.home ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: <Widget>[
        Text(i.player.isNotEmpty ? i.player : i.detail,
            style:
                AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        if (i.assist.isNotEmpty)
          Text(context.l10n.sportDetailAssist(i.assist),
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textTertiary)),
        if (i.comment.isNotEmpty && !i.isGoal)
          Text(i.comment,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textTertiary)),
      ],
    );
    final Widget minute = SizedBox(
      width: 36,
      child: Text(i.minute == null ? '' : "${i.minute}'",
          textAlign: TextAlign.center,
          style:
              AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary)),
    );
    // Domicile à gauche, extérieur à droite : la chronologie se lit comme
    // sur un tableau de stade.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: i.home
                ? Row(children: <Widget>[
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: text),
                  ])
                : const SizedBox.shrink(),
          ),
          minute,
          Expanded(
            child: i.home
                ? const SizedBox.shrink()
                : Row(children: <Widget>[
                    Expanded(child: text),
                    const SizedBox(width: 8),
                    Icon(icon, size: 16, color: color),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _statsTab() {
    final MatchDetail? d = _detail;
    if (d == null || d.stats.isEmpty) return _noData();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        for (final MatchStat s in d.stats) ExpandableStatRow(stat: s),
      ],
    );
  }

  Widget _cornersTab() {
    final MatchDetail? d = _detail;
    if (d == null || d.stats.isEmpty) return _noData();
    // Les corners d'abord, en grand ; puis les autres coups de pied arrêtés
    // qui vont avec (coups francs, hors-jeu), tous dépliables.
    final List<MatchStat> rows = <MatchStat>[
      for (final String k in <String>['corner', 'free kick', 'offside'])
        if (d.stat(k) != null) d.stat(k)!,
    ];
    if (rows.isEmpty) return _noData();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        for (int i = 0; i < rows.length; i++)
          ExpandableStatRow(stat: rows[i], initiallyExpanded: i == 0),
      ],
    );
  }

  Widget _cardsTab() {
    final MatchDetail? d = _detail;
    if (d == null) return _noData();
    final List<MatchIncident> cards = d.cards;
    final MatchStat? yellow = d.stat('yellow');
    final MatchStat? red = d.stat('red');
    if (cards.isEmpty && yellow == null && red == null) return _noData();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        if (yellow != null)
          ExpandableStatRow(stat: yellow, accent: AppColors.warning),
        if (red != null) ExpandableStatRow(stat: red, accent: AppColors.live),
        const SizedBox(height: 8),
        for (final MatchIncident c in cards) _incidentRow(c),
      ],
    );
  }

  Widget _lineupsTab() {
    final MatchDetail? d = _detail;
    if (d == null || (d.homeLineup.isEmpty && d.awayLineup.isEmpty)) {
      return _noData();
    }
    Widget column(List<MatchPlayer> ps, String formation, bool home) {
      final List<MatchPlayer> starters =
          ps.where((MatchPlayer p) => !p.substitute).toList();
      final List<MatchPlayer> subs =
          ps.where((MatchPlayer p) => p.substitute).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (formation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(formation,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.accent)),
            ),
          for (final MatchPlayer p in starters) _playerRow(p),
          if (subs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(context.l10n.sportDetailSubstitutes.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            for (final MatchPlayer p in subs) _playerRow(p, muted: true),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: column(d.homeLineup, d.homeFormation, true)),
          const SizedBox(width: 12),
          Expanded(child: column(d.awayLineup, d.awayFormation, false)),
        ],
      ),
    );
  }

  Widget _playerRow(MatchPlayer p, {bool muted = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Text(p.number?.toString() ?? '',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textTertiary)),
            ),
            Expanded(
              child: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: muted
                          ? AppColors.textSecondary
                          : AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

// =================================================================
//  Briques réutilisées par la liste (carte de match) et par la fiche
// =================================================================

/// Le badge rouge « LIVE ».
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.live,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          context.l10n.sportLiveBadge,
          style: AppTextStyles.labelSmall.copyWith(
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );
}

/// Texte qui CLIGNOTE (la minute d'un match en cours). Un seul minuteur
/// par instance, arrêté avec le widget : rien ne survit à l'écran.
class BlinkingText extends StatefulWidget {
  const BlinkingText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<BlinkingText> {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _on ? 1 : 0.25,
        duration: const Duration(milliseconds: 350),
        child: Text(widget.text, style: widget.style),
      );
}

/// Une statistique dépliable « comme SofaScore » : repliée, le nom et les
/// deux chiffres avec une barre ; dépliée, la barre en grand avec les
/// pourcentages de chaque camp. Le toucher bascule.
class ExpandableStatRow extends StatefulWidget {
  const ExpandableStatRow({
    super.key,
    required this.stat,
    this.initiallyExpanded = false,
    this.accent,
  });
  final MatchStat stat;
  final bool initiallyExpanded;
  final Color? accent;

  @override
  State<ExpandableStatRow> createState() => _ExpandableStatRowState();
}

class _ExpandableStatRowState extends State<ExpandableStatRow> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final MatchStat s = widget.stat;
    final Color accent = widget.accent ?? AppColors.accent;
    final double share = s.homeShare;
    final int homePct = (share * 100).round();
    final String h = s.home?.toString() ?? '–';
    final String a = s.away?.toString() ?? '–';
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: _open ? 12 : 8),
        decoration: BoxDecoration(
          color: _open ? AppColors.surfaceHigh : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(h,
                    style: (_open
                            ? AppTextStyles.headlineMedium
                            : AppTextStyles.bodyMedium)
                        .copyWith(fontWeight: FontWeight.w800)),
                Expanded(
                  child: Text(s.name,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondary)),
                ),
                Text(a,
                    style: (_open
                            ? AppTextStyles.headlineMedium
                            : AppTextStyles.bodyMedium)
                        .copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: _open ? 8 : 4,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: (share * 1000).round().clamp(1, 999),
                      child: Container(color: accent),
                    ),
                    Expanded(
                      flex: ((1 - share) * 1000).round().clamp(1, 999),
                      child: Container(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (_open) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('$homePct %',
                      style: AppTextStyles.labelSmall.copyWith(color: accent)),
                  Text('${100 - homePct} %',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
