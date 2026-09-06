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
import '../data/live_scores_service.dart';
import '../data/sports_repository.dart';
import '../domain/sport_models.dart';
import 'prediction_bar.dart';
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
  StreamSubscription<void>? _liveSub;

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
    //  SCORES EN DIRECT. Le service ne tourne QUE tant que cet écran est
    //  ouvert (cf. start/stop) : un minuteur qui lui survivrait viderait
    //  la batterie pour des données que personne ne regarde.
    LiveScoresService.instance.start();
    _liveSub = LiveScoresService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _followSub?.cancel();
    _favSub?.cancel();
    _liveSub?.cancel();
    LiveScoresService.instance.stop();
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
          _liveBand(),
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

  // ---------------------------------------------------------------
  //  BANDEAU « EN DIRECT »
  // ---------------------------------------------------------------
  //  C'est LA raison de rouvrir l'application. Une liste d'horaires se
  //  consulte une fois ; un score qui bouge se regarde dix fois dans une
  //  soirée. Il est donc EN HAUT, avant les filtres.
  //
  //  Il DISPARAÎT complètement quand rien ne se joue. Un bandeau vide
  //  intitulé « en direct » est pire que pas de bandeau du tout : il
  //  occupe la place et n'apprend rien.
  Widget _liveBand() {
    final List<SportEvent> live = LiveScoresService.instance.live;
    if (live.isEmpty) return const SizedBox.shrink();
    // On respecte le filtre de discipline : si le client regarde le
    // tennis, on ne lui impose pas le baseball en bandeau.
    final List<SportEvent> items = _sportFilter == null
        ? live
        : live.where((SportEvent e) => e.sport == _sportFilter).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Le point rouge : le seul élément animé de l'écran. Il
              // signale que ces chiffres-là ne sont pas figés.
              const _LiveDot(),
              const SizedBox(width: 6),
              Text(
                context.l10n.sportLiveNow.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: AppColors.live,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length}',
                style: AppTextStyles.labelSmall
                    .copyWith(fontSize: 10, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Borné : sur un téléphone à 256 Mo, on ne construit pas
              // 60 cartes avec deux images chacune pour une bande qu'on
              // fait défiler du pouce.
              itemCount: items.length > 12 ? 12 : items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext _, int i) =>
                  _LiveCard(event: items[i]),
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

/// Le point rouge du bandeau « en direct ». Extrait en widget `const` :
/// il est reconstruit à chaque rafraîchissement de score (toutes les
/// 45 s) et n'a aucune raison de l'être.
class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.live,
          shape: BoxShape.circle,
        ),
      );
}

/// Une carte du bandeau EN DIRECT : écusson, score, minute de jeu.
/// Volontairement DENSE et sans fioriture — c'est un tableau d'affichage,
/// pas une fiche. On doit pouvoir en lire quatre d'un coup d'œil.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.event});
  final SportEvent event;

  @override
  Widget build(BuildContext context) {
    final SportEvent e = event;
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        // Un liseré rouge discret plutôt qu'un fond coloré : sur un écran
        // de téléphone, un aplat rouge derrière du texte fatigue vite.
        border: Border.all(color: AppColors.live.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  e.league,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 9, color: AppColors.textTertiary),
                ),
              ),
              Text(
                e.liveLabel,
                style: AppTextStyles.labelSmall
                    .copyWith(fontSize: 10, color: AppColors.live),
              ),
            ],
          ),
          _liveSide(e.homeBadge, e.home, e.homeScore),
          _liveSide(e.awayBadge, e.away, e.awayScore),
        ],
      ),
    );
  }

  /// Une ligne « écusson · équipe · score ». Le score est à droite,
  /// aligné entre les deux lignes : c'est ce qui rend un tableau de
  /// scores lisible sans le lire vraiment.
  Widget _liveSide(String badge, String team, String? score) {
    return Row(
      children: <Widget>[
        if (badge.isNotEmpty) _TeamBadge(url: badge),
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall,
          ),
        ),
        Text(
          (score == null || score.isEmpty) ? '–' : score,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Écusson d'équipe. Petit, borné, et surtout TOLÉRANT : une URL morte ne
/// doit ni faire un carré gris, ni décaler la ligne. `errorBuilder` rend
/// alors un espace vide de la même taille — le texte ne bouge pas.
///
/// `cacheWidth` est là pour les petits téléphones : sans lui, Flutter
/// décode l'image à sa taille NATIVE (souvent 500 px) pour l'afficher en
/// 18 px, et garde le tout en mémoire. Sur un 256 Mo, vingt écussons
/// suffisent à faire mal.
class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.url});
  final String url;

  static const double _size = 18;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Image.network(
          url,
          width: _size,
          height: _size,
          cacheWidth: (_size * 3).round(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          // Pas d'indicateur de chargement : sur une liste, vingt petits
          // ronds qui tournent font plus de bruit que de service.
          loadingBuilder: (BuildContext _, Widget child,
                  ImageChunkEvent? p) =>
              p == null ? child : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Étiquette « Féminin ». On ne CACHE pas les compétitions féminines : on
/// les NOMME. Sans cette étiquette, « Italian Serie A Womens Cup »
/// s'afficherait « Serie A » et le client croirait voir le championnat
/// masculin — c'est le genre de confusion qui fait désinstaller une app.
class _WomenChip extends StatelessWidget {
  const _WomenChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        context.l10n.sportWomen,
        style: AppTextStyles.labelSmall
            .copyWith(fontSize: 9, color: AppColors.textSecondary),
      ),
    );
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
    //  LE SCORE EN DIRECT EST INJECTÉ ICI, au dernier moment. L'affiche
    //  garde son heure, ses écussons et son niveau ; seul ce qui bouge
    //  (score, minute) vient du service temps réel.
    final SportEvent e = LiveScoresService.instance.enrich(widget.event);
    final bool followed = FollowedMatchesService.instance.isFollowed(e.id);

    //  AVANT le 23/08, « en direct » était DEVINÉ à l'horloge : un match
    //  dont l'heure était passée de moins de 2 h était déclaré en cours.
    //  C'était faux la moitié du temps — un match reporté, une prolongation,
    //  un fuseau mal lu, et le badge mentait. Maintenant la source le DIT :
    //  on n'affiche « EN DIRECT » que si le match est vraiment dans la
    //  liste des rencontres en cours.
    final bool live = LiveScoresService.instance.forId(e.id) != null && e.isLive;

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
                            // La MINUTE de jeu plutôt que le mot « direct » :
                            // « 67' » dit à la fois que ça joue ET où on en
                            // est. C'est ce qui donne envie de rester.
                            e.liveLabel.isEmpty
                                ? context.l10n.sportLive
                                : e.liveLabel,
                            style: AppTextStyles.labelSmall.copyWith(
                                fontSize: 9, color: AppColors.live),
                          ),
                        ),
                      if (e.women) const _WomenChip(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      // Les écussons se lisent plus vite qu'un nom. Ils
                      // disparaissent proprement quand la source ne les a
                      // pas : aucune place réservée « en attendant ».
                      if (e.homeBadge.isNotEmpty) _TeamBadge(url: e.homeBadge),
                      if (e.awayBadge.isNotEmpty) _TeamBadge(url: e.awayBadge),
                      Expanded(
                        child: Text(
                          e.isDuel ? '${e.home} – ${e.away}' : e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                      if (e.hasScore)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '${e.homeScore}–${e.awayScore}',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: live ? AppColors.live : AppColors.textPrimary,
                            ),
                          ),
                        ),
                    ],
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
                  // PRONOSTIC DES FANS (06/09) : « 1 · N · 2 » avant le
                  // coup d'envoi, pourcentages après le vote, figé au
                  // coup d'envoi. Ne rend rien pour une course.
                  PredictionBar(event: e),
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
