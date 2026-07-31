// =========================================================
//  sports_screen.dart — Centre Sportif (téléphone)
// =========================================================
//  Portage mobile de l'écran sport TV (tv_sports_screen) : mêmes données
//  (SportsRepository → Worker → TheSportsDB, cache 10 min), même
//  périmètre HONNÊTE — derniers résultats + prochains matchs des équipes
//  suivies, recherche internationale d'équipes, rappels automatiques
//  ~1 h avant chaque match (déjà gérés par le repository).
//
//  Ce qu'on n'affiche PAS (pas de source fiable temps réel en gratuit) :
//  minute en direct, buteurs, cotes. La fraîcheur des données est
//  affichée (« MàJ » = heure du dernier rafraîchissement) plutôt que de
//  faire croire à du temps réel — règle : jamais de donnée inventée.
//
//  Texte : uniquement des clés l10n existantes (aucune chaîne en dur).
//  Aucune dépendance au cast.
// =========================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/sports_repository.dart';
import '../domain/sport_models.dart';

class SportsScreen extends StatefulWidget {
  const SportsScreen({super.key});

  @override
  State<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends State<SportsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<SportTeam> _results = const <SportTeam>[];
  bool _searching = false;
  StreamSubscription<void>? _changesSub;
  StreamSubscription<List<SportTeam>>? _favSub;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    // Idempotent : déjà appelé côté TV au boot, pas côté téléphone.
    unawaited(SportsRepository.instance.initialize());
    _changesSub = SportsRepository.instance.changesStream.listen((_) {
      if (mounted) setState(() => _lastSync = DateTime.now());
    });
    _favSub = SportsRepository.instance.favoritesStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changesSub?.cancel();
    _favSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _results = const <SportTeam>[];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searching = true);
      final List<SportTeam> r =
          await SportsRepository.instance.search(q.trim());
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    });
  }

  Future<void> _toggleFavorite(SportTeam team) async {
    final SportsRepository repo = SportsRepository.instance;
    if (repo.isFavorite(team.id)) {
      await repo.removeFavorite(team.id);
    } else {
      await repo.addFavorite(team);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<SportTeam> favorites = SportsRepository.instance.favorites;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(context.l10n.genreSports, style: AppTextStyles.headlineMedium),
        actions: <Widget>[
          if (_lastSync != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Fraîcheur AFFICHÉE (honnêteté) : heure du dernier sync,
                  // icône + HH:MM — pas de texte (i18n sans nouvelle clé).
                  const Icon(Icons.sync_rounded,
                      size: 13, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${_lastSync!.hour.toString().padLeft(2, '0')}:'
                    '${_lastSync!.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: <Widget>[
          // ----- Recherche d'équipe (internationale) -----
          TextField(
            controller: _searchCtrl,
            onChanged: _onQueryChanged,
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: context.l10n.tvTeamPickerHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: AppColors.maisonSurfaceHigh.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (!_searching &&
              _results.isEmpty &&
              _searchCtrl.text.trim().length >= 3)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                context.l10n.tvNoTeamFound,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ..._results.map((SportTeam t) => _TeamRow(
                team: t,
                isFavorite: SportsRepository.instance.isFavorite(t.id),
                onToggle: () => _toggleFavorite(t),
              )),

          // ----- Mes équipes -----
          const SizedBox(height: 18),
          Text(context.l10n.tvMyTeams,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 17)),
          const SizedBox(height: 8),
          if (favorites.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.maisonSurfaceHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.sports_soccer_rounded,
                      color: AppColors.accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.tvSportPickIntro,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ...favorites.map((SportTeam t) => _FavoriteTeamCard(
                  team: t,
                  events: SportsRepository.instance.eventsFor(t.id),
                  onRemove: () => _toggleFavorite(t),
                )),
        ],
      ),
    );
  }
}

/// Ligne de résultat de recherche : badge + nom + ligue + cœur.
class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.team,
    required this.isFavorite,
    required this.onToggle,
  });

  final SportTeam team;
  final bool isFavorite;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppColors.maisonSurfaceHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                _TeamBadge(url: team.badge, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLarge
                              .copyWith(fontWeight: FontWeight.w700)),
                      if (team.league.isNotEmpty)
                        Text(team.league,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? AppColors.live : AppColors.textTertiary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte d'une équipe suivie : dernier match (score) + prochain match.
class _FavoriteTeamCard extends StatelessWidget {
  const _FavoriteTeamCard({
    required this.team,
    required this.events,
    required this.onRemove,
  });

  final SportTeam team;
  final SportsEvents events;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final SportEvent? last =
        events.last.isNotEmpty ? events.last.first : null;
    final SportEvent? next =
        events.next.isNotEmpty ? events.next.first : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.maisonSurfaceHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _TeamBadge(url: team.badge, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.w800)),
                    if (team.league.isNotEmpty)
                      Text(team.league,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 11.5,
                              color: AppColors.textTertiary)),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.favorite_rounded,
                    color: AppColors.live, size: 20),
                onPressed: onRemove,
              ),
            ],
          ),
          if (last != null) ...<Widget>[
            const SizedBox(height: 10),
            _EventLine(
              label: context.l10n.tvSportLastMatch,
              event: last,
              showScore: true,
            ),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: 8),
            _EventLine(
              label: context.l10n.tvSportNextMatch,
              event: next,
              showScore: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// Une ligne match : libellé + « A 2–1 B » (ou « A vs B · date heure »).
class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.label,
    required this.event,
    required this.showScore,
  });

  final String label;
  final SportEvent event;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final String vs = context.l10n.tvSportVersus;
    String main;
    if (showScore && event.hasScore) {
      main = '${event.home} ${event.homeScore}–${event.awayScore} '
          '${event.away}';
    } else {
      main = '${event.home} $vs ${event.away}';
    }
    final DateTime? dt = event.startsAt;
    final String when = dt == null
        ? ''
        : ' · ${dt.day.toString().padLeft(2, '0')}/'
            '${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            showScore ? main : '$main$when',
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// Badge d'équipe avec repli icône ballon (jamais de spinner).
class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.sports_soccer_rounded,
          color: AppColors.accent, size: size * 0.55),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 3).round(),
        memCacheHeight: (size * 3).round(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}
