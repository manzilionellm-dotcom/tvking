// =========================================================
//  sport_screen.dart — Le coin SPORT du téléphone
// =========================================================
//  Demande propriétaire (23/08) : « ajoute tout un coin dédié au sport…
//  la catégorie, tous les sports, même le basket, même le tennis, tout…
//  quelqu'un peut choisir les matchs où il veut suivre. »
//
//  Le sport n'existait que sur la TV. Côté téléphone il n'y avait que les
//  notifications, sans aucun écran — donc rien à régler, rien à voir.
//
//  TROIS ONGLETS, dans l'ordre de ce qu'on regarde le plus souvent :
//    1. À L'AFFICHE — les grandes rencontres des 3 prochains jours, tous
//       sports confondus, filtrables par discipline. Chaque ligne a un
//       bouton « suivre » : c'est LÀ qu'on choisit match par match.
//    2. MES MATCHS  — ce qu'on a choisi de suivre. Servi depuis la
//       mémoire locale : instantané, et lisible même sans réseau.
//    3. MES ÉQUIPES — les équipes favorites (tous leurs matchs comptent).
//
//  QUAND LA SOURCE EST MUETTE : on n'affiche PAS un écran vide. Un écran
//  vide se lit « l'app est cassée » ; on distingue donc explicitement
//  « aucune rencontre ces jours-ci » de « la source ne répond pas », en
//  s'appuyant sur les compteurs que le serveur renvoie (upstream_ko).
//
//  PETITS TÉLÉPHONES : aucune image de fond, aucune affiche, listes
//  paresseuses et bornées. L'écran doit s'ouvrir sur un 256 Mo.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../data/followed_matches_service.dart';
import '../data/sports_repository.dart';
import '../domain/sport_models.dart';
import 'team_picker_sheet.dart';

/// Résultat d'un chargement des affiches : les matchs ET l'état de la
/// source. Les deux voyagent ensemble, sinon l'écran ne peut pas faire la
/// différence entre « rien à afficher » et « rien ne répond ».
@immutable
class _BigLoad {
  const _BigLoad({
    this.matches = const <SportEvent>[],
    this.sourceDown = false,
  });

  final List<SportEvent> matches;

  /// `true` quand le serveur a bien répondu mais n'a joint AUCUNE de ses
  /// sources en amont — donc l'absence de match ne veut rien dire.
  final bool sourceDown;
}

class SportScreen extends StatefulWidget {
  const SportScreen({super.key});

  @override
  State<SportScreen> createState() => _SportScreenState();
}

class _SportScreenState extends State<SportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  _BigLoad _load = const _BigLoad();
  bool _loading = true;
  bool _failed = false;

  /// Discipline sélectionnée dans la barre de filtres (`null` = toutes).
  String? _sportFilter;

  StreamSubscription<void>? _followSub;
  StreamSubscription<List<SportTeam>>? _favSub;

  @override
  void initState() {
    super.initState();
    unawaited(FollowedMatchesService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }));
    unawaited(SportsRepository.instance.initialize());
    _followSub = FollowedMatchesService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _favSub = SportsRepository.instance.favoritesStream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_fetch());
  }

  @override
  void dispose() {
    _followSub?.cancel();
    _favSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (mounted) setState(() => _loading = true);
    _BigLoad result = const _BigLoad();
    bool failed = false;
    try {
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/big'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        failed = true;
      } else {
        final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          failed = true;
        } else {
          final List<SportEvent> evs = <SportEvent>[];
          final Object? list = decoded['matches'];
          if (list is List) {
            for (final Object? raw in list) {
              if (raw is! Map<String, dynamic>) continue;
              final SportEvent ev = SportEvent.fromJson(raw);
              if (ev.id.isNotEmpty) evs.add(ev);
            }
          }
          // La source est « muette » quand le serveur n'a joint AUCUN de
          // ses fournisseurs. C'est ce qui permet d'écrire « le service
          // ne répond pas » au lieu d'un écran vide trompeur.
          final int ok = (decoded['upstream_ok'] as num?)?.toInt() ?? -1;
          final int ko = (decoded['upstream_ko'] as num?)?.toInt() ?? 0;
          // Les disciplines proposées en filtre se déduisent des matchs
          // reçus, pas du champ `sports` du serveur : elles restent ainsi
          // toujours cohérentes avec ce qui est réellement affiché.
          result = _BigLoad(matches: evs, sourceDown: ok == 0 && ko > 0);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Sport] chargement KO: $e');
      failed = true;
    }
    // Le suivi mémorisé se rafraîchit avec ce qui vient d'arriver : les
    // scores des matchs suivis restent lisibles hors ligne ensuite.
    if (result.matches.isNotEmpty) {
      unawaited(FollowedMatchesService.instance.refreshKnown(result.matches));
    }
    if (!mounted) return;
    setState(() {
      _load = result;
      _failed = failed;
      _loading = false;
    });
  }

  /// Disciplines proposées dans la barre de filtres : celles réellement
  /// présentes dans les affiches du moment (pas une liste en dur, qui
  /// afficherait « Tennis » un jour sans tennis).
  List<String> get _availableSports {
    final Set<String> s = <String>{};
    for (final SportEvent e in _load.matches) {
      if (e.sport.isNotEmpty) s.add(e.sport);
    }
    final List<String> list = s.toList()..sort();
    return list;
  }

  List<SportEvent> get _filtered {
    if (_sportFilter == null) return _load.matches;
    return _load.matches
        .where((SportEvent e) => e.sport == _sportFilter)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(context.l10n.navSport, style: AppTextStyles.headlineMedium),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.sportRefresh,
            onPressed: _loading ? null : () => unawaited(_fetch()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.accent,
          labelStyle: AppTextStyles.labelSmall.copyWith(fontSize: 12),
          tabs: <Widget>[
            Tab(text: context.l10n.sportTabHighlights),
            Tab(text: context.l10n.sportTabFollowed),
            Tab(text: context.l10n.sportTabTeams),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _highlightsTab(),
          _followedTab(),
          _teamsTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  //  1. À l'affiche
  // ---------------------------------------------------------------

  Widget _highlightsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // TROIS messages distincts, jamais un écran vide muet : le client doit
    // pouvoir dire si le problème vient de lui, de nous, ou de personne.
    if (_failed) {
      return _empty(
        icon: Icons.wifi_off_rounded,
        title: context.l10n.sportOfflineTitle,
        body: context.l10n.sportOfflineBody,
        onRetry: () => unawaited(_fetch()),
      );
    }
    if (_load.sourceDown) {
      return _empty(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.sportSourceDownTitle,
        body: context.l10n.sportSourceDownBody,
        onRetry: () => unawaited(_fetch()),
      );
    }
    final List<SportEvent> items = _filtered;
    if (items.isEmpty && _load.matches.isEmpty) {
      return _empty(
        icon: Icons.event_busy_rounded,
        title: context.l10n.sportNoneTitle,
        body: context.l10n.sportNoneBody,
        onRetry: () => unawaited(_fetch()),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _fetch,
      child: Column(
        children: <Widget>[
          _sportFilterBar(),
          Expanded(
            child: items.isEmpty
                // Filtre trop restrictif : il y a des matchs, mais aucun
                // dans cette discipline. On le dit, plutôt que de laisser
                // croire que tout est vide.
                ? _empty(
                    icon: Icons.filter_alt_off_rounded,
                    title: context.l10n.sportNoneInSportTitle,
                    body: context.l10n.sportNoneInSportBody,
                    onRetry: () => setState(() => _sportFilter = null),
                    retryLabel: context.l10n.sportShowAll,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: items.length,
                    itemBuilder: (BuildContext _, int i) =>
                        _MatchTile(event: items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sportFilterBar() {
    final List<String> sports = _availableSports;
    if (sports.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        itemCount: sports.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return _Chip(
              label: context.l10n.sportAll,
              active: _sportFilter == null,
              onTap: () => setState(() => _sportFilter = null),
            );
          }
          final String s = sports[i - 1];
          return _Chip(
            label: localizedSportName(context, s),
            active: _sportFilter == s,
            onTap: () => setState(() => _sportFilter = s),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  //  2. Mes matchs suivis
  // ---------------------------------------------------------------

  Widget _followedTab() {
    final List<SportEvent> items = FollowedMatchesService.instance.all;
    if (items.isEmpty) {
      return _empty(
        icon: Icons.notifications_active_outlined,
        title: context.l10n.sportFollowedEmptyTitle,
        body: context.l10n.sportFollowedEmptyBody,
        onRetry: () => _tabs.animateTo(0),
        retryLabel: context.l10n.sportTabHighlights,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: items.length,
      itemBuilder: (BuildContext _, int i) => _MatchTile(event: items[i]),
    );
  }

  // ---------------------------------------------------------------
  //  3. Mes équipes
  // ---------------------------------------------------------------

  Widget _teamsTab() {
    final List<SportTeam> teams = SportsRepository.instance.favorites;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await showTeamPickerSheet(context);
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: Text(context.l10n.sportAddTeam),
            ),
          ),
        ),
        if (teams.isEmpty)
          Expanded(
            child: _empty(
              icon: Icons.groups_outlined,
              title: context.l10n.sportTeamsEmptyTitle,
              body: context.l10n.sportTeamsEmptyBody,
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: teams.length,
              itemBuilder: (BuildContext _, int i) {
                final SportTeam t = teams[i];
                return Card(
                  color: AppColors.surface,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(t.name, style: AppTextStyles.bodyMedium),
                    subtitle: t.league.isEmpty
                        ? null
                        : Text(t.league,
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textTertiary)),
                    trailing: IconButton(
                      tooltip: context.l10n.sportRemoveTeam,
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary),
                      onPressed: () async {
                        await SportsRepository.instance.removeFavorite(t.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------

  Widget _empty({
    required IconData icon,
    required String title,
    required String body,
    VoidCallback? onRetry,
    String? retryLabel,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
        // Défilable : indispensable pour que « tirer pour rafraîchir »
        // fonctionne aussi quand la liste est vide.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 44, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge),
                  const SizedBox(height: 8),
                  Text(body,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textTertiary)),
                  if (onRetry != null) ...<Widget>[
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent),
                      child: Text(retryLabel ?? context.l10n.sportRetry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nom de discipline traduit. Le panel renvoie l'anglais (« Soccer »,
/// « Ice Hockey »…) ; on affiche le français quand on le connaît, et le
/// libellé brut sinon — jamais une case vide.
String localizedSportName(BuildContext context, String raw) {
  switch (raw.toLowerCase()) {
    case 'soccer':
      return context.l10n.sportSoccer;
    case 'basketball':
      return context.l10n.sportBasketball;
    case 'tennis':
      return context.l10n.sportTennis;
    case 'ice hockey':
      return context.l10n.sportIceHockey;
    case 'american football':
      return context.l10n.sportAmericanFootball;
    case 'motorsport':
      return context.l10n.sportMotorsport;
    case 'rugby':
      return context.l10n.sportRugby;
    case 'baseball':
      return context.l10n.sportBaseball;
    default:
      return raw;
  }
}

/// Une rencontre + le bouton « suivre ». C'est la brique qui répond à
/// « quelqu'un peut choisir les matchs où il veut suivre ».
class _MatchTile extends StatefulWidget {
  const _MatchTile({required this.event});
  final SportEvent event;

  @override
  State<_MatchTile> createState() => _MatchTileState();
}

class _MatchTileState extends State<_MatchTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final SportEvent e = widget.event;
    final bool followed = FollowedMatchesService.instance.isFollowed(e.id);
    final DateTime? when = e.startsAt;
    final bool live = when != null &&
        !e.hasScore &&
        DateTime.now().difference(when).inMinutes.abs() < 120 &&
        when.isBefore(DateTime.now());

    return Card(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (e.sport.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            localizedSportName(context, e.sport).toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 9,
                              letterSpacing: 0.8,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      if (live)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.live.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            context.l10n.sportLive,
                            style: AppTextStyles.labelSmall.copyWith(
                                fontSize: 9, color: AppColors.live),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.home.isNotEmpty && e.away.isNotEmpty
                        ? '${e.home} – ${e.away}'
                        : e.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      if (e.hasScore) '${e.homeScore} – ${e.awayScore}',
                      if (e.whenLabel.isNotEmpty) e.whenLabel,
                      if (e.league.isNotEmpty) e.league,
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: followed
                  ? context.l10n.sportUnfollow
                  : context.l10n.sportFollow,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final bool now =
                          await FollowedMatchesService.instance.toggle(e);
                      if (!mounted) return;
                      setState(() => _busy = false);
                      final ScaffoldMessengerState? m =
                          ScaffoldMessenger.maybeOf(context);
                      m?.showSnackBar(SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(now
                            ? context.l10n.sportFollowedOn
                            : context.l10n.sportFollowedOff),
                      ));
                    },
              icon: Icon(
                followed
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: followed ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.surfaceHigh,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: active ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
