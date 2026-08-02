// =========================================================
//  tv_team_picker_screen.dart — Choisir SON équipe préférée (10-foot)
// =========================================================
//  Clavier à l'écran (D-pad, instance STABLE = pas de perte de focus) à gauche ;
//  résultats TheSportsDB (via le Worker) à droite. OK sur une équipe → on la
//  renvoie à l'appelant (Navigator.pop(team)).
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

/// Catalogue VIP : les grandes équipes par sport. On stocke des NOMS ; au clic,
/// on résout l'équipe (id + logo) via la recherche TheSportsDB (Worker). Ainsi
/// le client choisit en UN clic, sans rien taper.
const Map<String, List<String>> _kVipTeams = <String, List<String>>{
  'Football': <String>[
    'Real Madrid', 'Barcelona', 'Manchester United', 'Manchester City',
    'Liverpool', 'Arsenal', 'Chelsea', 'Tottenham', 'Paris SG',
    'Bayern Munich', 'Borussia Dortmund', 'Juventus', 'AC Milan',
    'Inter Milan', 'Napoli', 'Atletico Madrid', 'Ajax', 'Porto',
    'Benfica', 'Marseille',
  ],
  'Basket (NBA)': <String>[
    'Los Angeles Lakers', 'Boston Celtics', 'Golden State Warriors',
    'Chicago Bulls', 'Miami Heat', 'Milwaukee Bucks', 'Brooklyn Nets',
    'Denver Nuggets', 'New York Knicks', 'Dallas Mavericks',
  ],
  'Rugby': <String>[
    'Leinster', 'Toulouse', 'Saracens', 'Leicester Tigers',
    'Stade Francais', 'Munster',
  ],
  'NFL': <String>[
    'Kansas City Chiefs', 'Dallas Cowboys', 'New England Patriots',
    'Green Bay Packers', 'San Francisco 49ers', 'Buffalo Bills',
  ],
};

class TvTeamPickerScreen extends StatefulWidget {
  const TvTeamPickerScreen({super.key});

  @override
  State<TvTeamPickerScreen> createState() => _TvTeamPickerScreenState();
}

class _TvTeamPickerScreenState extends State<TvTeamPickerScreen> {
  String _q = '';
  List<SportTeam> _results = const <SportTeam>[];
  bool _loading = false;
  bool _resolving = false; // en train de résoudre une équipe du catalogue VIP
  String? _msg; // petit message (équipe introuvable…)
  Timer? _debounce;
  Timer? _msgTimer;

  // Instance STABLE → non reconstruite à chaque frappe (focus préservé).
  late final Widget _keyboard =
      _PickerKeyboard(onType: _type, onBackspace: _backspace, onClear: _clear);

  @override
  void dispose() {
    _debounce?.cancel();
    _msgTimer?.cancel();
    super.dispose();
  }

  // Clic sur une équipe du catalogue VIP (on n'a que le nom) → on résout l'id +
  // le logo via la recherche, puis on renvoie l'équipe à l'appelant.
  Future<void> _resolveAndPick(String name) async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _msg = null;
    });
    final List<SportTeam> r = await SportsRepository.instance.search(name);
    if (!mounted) return;
    setState(() => _resolving = false);
    if (r.isEmpty) {
      _flash(context.l10n.tvSportTeamNotFound(name));
      return;
    }
    final SportTeam best = r.firstWhere(
      (SportTeam t) => t.name.toLowerCase() == name.toLowerCase(),
      orElse: () => r.first,
    );
    if (mounted) Navigator.of(context).pop(best);
  }

  void _flash(String m) {
    setState(() => _msg = m);
    _msgTimer?.cancel();
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  void _type(String c) {
    setState(() => _q += c);
    _schedule();
  }

  void _backspace() {
    if (_q.isEmpty) return;
    setState(() => _q = _q.substring(0, _q.length - 1));
    _schedule();
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _q = '';
      _results = const <SportTeam>[];
    });
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _run);
  }

  Future<void> _run() async {
    final String q = _q.trim();
    if (q.length < 2) {
      if (mounted) setState(() => _results = const <SportTeam>[]);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final List<SportTeam> r = await SportsRepository.instance.search(q);
    if (mounted) {
      setState(() {
        _results = r;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 380, child: _keyboard),
        const SizedBox(width: TvDimens.gutter),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                ),
                child: Text(
                  _q.isEmpty ? context.l10n.tvTeamPickerHint : _q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w700,
                      color: _q.isEmpty ? TvTokens.mutedDim : TvTokens.text),
                ),
              ),
              const SizedBox(height: 14),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_msg!,
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.live)),
                ),
              Expanded(child: _resultsView()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultsView() {
    if (_resolving) {
      return const Center(
        child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 3, color: TvTokens.gold)),
      );
    }
    // Requête vide → CATALOGUE VIP : on choisit une grande équipe en 1 clic.
    if (_q.trim().isEmpty) return _catalogView();
    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(strokeWidth: 3, color: TvTokens.gold)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoTeamFound,
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        final SportTeam t = _results[i];
        return TvFocusable(
          autofocus: i == 0,
          scale: TvFocusScale.medium,
          baseColor: TvTokens.card,
          onSelect: () => Navigator.of(context).pop(t),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 44,
                  height: 44,
                  child: t.badge.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: t.badge,
                          fit: BoxFit.contain, memCacheWidth: 120,
                          fadeInDuration: const Duration(milliseconds: 150),
                          placeholder: (_, __) => const Icon(
                              Icons.shield_rounded, color: TvTokens.muted),
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.shield_rounded, color: TvTokens.muted))
                      : const Icon(Icons.shield_rounded, color: TvTokens.muted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: TvDimens.title,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                      const SizedBox(height: 2),
                      Text(
                          <String>[t.sport, t.league]
                              .where((String s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: TvDimens.label, color: TvTokens.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Catalogue VIP : sections par sport, chips d'équipes animées (focus or).
  Widget _catalogView() {
    final List<Widget> children = <Widget>[];
    bool first = true;
    bool sectionFirst = true;
    _kVipTeams.forEach((String sport, List<String> teams) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(2, sectionFirst ? 0 : 20, 2, 10),
        child: Text(sport.toUpperCase(),
            style: TvTokens.ui(14,
                weight: FontWeight.w700,
                color: TvTokens.mutedDim,
                spacing: 1.5)),
      ));
      sectionFirst = false;
      final List<Widget> chips = <Widget>[];
      for (final String name in teams) {
        chips.add(_teamChip(name, autofocus: first));
        first = false;
      }
      children.add(Wrap(spacing: 10, runSpacing: 10, children: chips));
    });
    return ListView(
      padding: const EdgeInsets.only(right: 6, bottom: 12),
      children: children,
    );
  }

  Widget _teamChip(String name, {bool autofocus = false}) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: () => _resolveAndPick(name),
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Text(name,
              style: TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w700,
                  color: focused ? TvTokens.onGold : TvTokens.text)),
        );
      },
    );
  }
}

class _PickerKeyboard extends StatelessWidget {
  const _PickerKeyboard(
      {required this.onType, required this.onBackspace, required this.onClear});
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const List<String> _keys = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvMyTeam,
            style: TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _keys.length; i++)
              _Key(label: _keys[i], onTap: () => onType(_keys[i])),
            _Key(label: '␣', wide: true, onTap: () => onType(' ')),
            _Key(label: '⌫', onTap: onBackspace),
            _Key(label: '✕', onTap: onClear),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(
      {required this.label, required this.onTap, this.wide = false, this.autofocus = false});
  final String label;
  final VoidCallback onTap;
  final bool wide;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 116 : 54,
      height: 54,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? TvTokens.gold : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: focused ? TvTokens.onGold : TvTokens.text)),
          );
        },
      ),
    );
  }
}
