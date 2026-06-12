// =========================================================
//  tv_app.dart — Racine de DeFew TV (MaterialApp 10-foot)
// =========================================================
//  Thème sombre, typo agrandie (§6-7). L'accueil pose le squelette de
//  navigation D-pad (rail gauche focusable) — les écrans Live / Guide /
//  Films / Séries / Recherche viendront se brancher dessus (BUILD_ORDER
//  5→9), en réutilisant les briques data du mobile.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import 'tv_activation_screen.dart';
import 'tv_components.dart';
import 'tv_live_screen.dart';
import 'tv_search_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TvTokens.bg,
      colorScheme: const ColorScheme.dark(
        surface: TvTokens.card,
        primary: TvTokens.gold,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Police par défaut = Inter (Maison Noir) sur TOUT le texte.
        textTheme: GoogleFonts.interTextTheme(base.textTheme)
            .apply(bodyColor: TvTokens.text, displayColor: TvTokens.text),
        // Coupe TOUT effet tactile (hover/splash souris) — D-pad only.
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
      ),
      home: const TvGate(),
    );
  }
}

/// Porte d'entrée. L'app s'ouvre si :
///   • l'appareil est PAYÉ (activé par le revendeur), OU
///   • le client a ajouté SA PROPRE liste (The Few ne vend pas de liste →
///     on lui donne le droit d'apporter sa playlist) → des chaînes locales.
/// Sinon → écran d'activation (prix + MAC + « J'ajoute ma propre liste »).
class TvGate extends StatefulWidget {
  const TvGate({super.key});
  @override
  State<TvGate> createState() => _TvGateState();
}

class _TvGateState extends State<TvGate> {
  StreamSubscription<List<Channel>>? _sub;

  @override
  void initState() {
    super.initState();
    SubscriptionState.instance.addListener(_onChange);
    _sub = PlaylistRepository.instance.channelsStream.listen((_) => _onChange());
  }

  @override
  void dispose() {
    SubscriptionState.instance.removeListener(_onChange);
    _sub?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool paid =
        SubscriptionState.instance.status == SubscriptionStatus.paid;
    final bool hasOwnList =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    if (paid || hasOwnList) return const TvHomeScreen();
    return const TvShell(child: TvActivationScreen());
  }
}

/// Destinations de la navigation principale (buckets §8 home).
enum TvDest { live, films, series, guide, search, settings }

extension on TvDest {
  String get label {
    switch (this) {
      case TvDest.live:
        return 'Direct';
      case TvDest.films:
        return 'Films';
      case TvDest.series:
        return 'Séries';
      case TvDest.guide:
        return 'Guide';
      case TvDest.search:
        return 'Recherche';
      case TvDest.settings:
        return 'Réglages';
    }
  }

  IconData get icon {
    switch (this) {
      case TvDest.live:
        return Icons.live_tv_rounded;
      case TvDest.films:
        return Icons.movie_rounded;
      case TvDest.series:
        return Icons.video_library_rounded;
      case TvDest.guide:
        return Icons.grid_view_rounded;
      case TvDest.search:
        return Icons.search_rounded;
      case TvDest.settings:
        return Icons.settings_rounded;
    }
  }
}

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  TvDest _selected = TvDest.live;

  @override
  Widget build(BuildContext context) {
    return TvShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _HomeHeader(),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ----- Rail de navigation (gauche) -----
                SizedBox(
                  width: 240,
                  child: _NavRail(
                    selected: _selected,
                    onSelect: (TvDest d) => setState(() => _selected = d),
                  ),
                ),
                const SizedBox(width: TvDimens.gutter),
                // ----- Panneau de contenu -----
                Expanded(child: _ContentPanel(dest: _selected)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tête personnalisé : Bonjour + ville • météo + heure locale en direct.
class _HomeHeader extends StatefulWidget {
  const _HomeHeader();
  @override
  State<_HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<_HomeHeader> {
  Greeting? _g;
  Timer? _clock;
  DateTime _now = DateTime.now();
  static const List<String> _days = <String>[
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
  ];

  @override
  void initState() {
    super.initState();
    GreetingRepository.instance.fetch().then((Greeting? g) {
      if (mounted) setState(() => _g = g);
    });
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _time =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
  String get _date => '${_days[(_now.weekday - 1).clamp(0, 6)]} $_time';

  @override
  Widget build(BuildContext context) {
    final Greeting? g = _g;
    final String weather = (g != null && g.tempC != null)
        ? ' · ${g.tempC!.round()}°C ${g.emoji}'
        : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Bonjour 👋', style: TvTokens.ui(30, weight: FontWeight.w600, color: TvTokens.text)),
            if (g != null && g.city.isNotEmpty)
              Text.rich(TextSpan(children: <InlineSpan>[
                TextSpan(text: g.city, style: TvTokens.ui(TvDimens.titleS, weight: FontWeight.w600, color: TvTokens.gold)),
                TextSpan(text: weather, style: TvTokens.ui(TvDimens.titleS, color: TvTokens.muted)),
              ])),
          ],
        ),
        const Spacer(),
        Text.rich(TextSpan(children: <InlineSpan>[
          TextSpan(text: _days[(_now.weekday - 1).clamp(0, 6)], style: TvTokens.ui(TvDimens.title, weight: FontWeight.w600, color: TvTokens.text)),
          TextSpan(text: ' · $_time', style: TvTokens.ui(TvDimens.title, color: TvTokens.muted)),
        ])),
      ],
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelect});

  final TvDest selected;
  final ValueChanged<TvDest> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const TvLogo(width: 150),
              const SizedBox(height: 6),
              Text('THE FEW TV',
                  style: TvTokens.ui(10, weight: FontWeight.w600, color: TvTokens.gold, spacing: 3.4)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (int i = 0; i < TvDest.values.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NavItem(
                    dest: TvDest.values[i],
                    selected: TvDest.values[i] == selected,
                    // Focus initial sur le 1er item (Direct).
                    autofocus: i == 0,
                    onSelect: () => onSelect(TvDest.values[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final TvDest dest;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        // Maison Noir : fond `--sel` au focus/actif, barre OR à gauche si
        // actif, texte or. JAMAIS de bloc blanc plein.
        final bool hl = focused || selected;
        final Color fg = hl ? TvTokens.goldBright : TvTokens.muted;
        return Container(
          height: 54,
          decoration: BoxDecoration(
            color: hl ? TvTokens.sel : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
          ),
          child: Row(
            children: <Widget>[
              // Barre or à gauche (item actif).
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected ? TvTokens.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 13),
              Icon(dest.icon, color: fg, size: 22),
              const SizedBox(width: 14),
              Text(dest.label,
                  style: TvTokens.ui(19,
                      weight: selected ? FontWeight.w600 : FontWeight.w500, color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.dest});

  final TvDest dest;

  @override
  Widget build(BuildContext context) {
    // « Direct » et « Réglages » sont branchés ; les autres buckets
    // arrivent (BUILD_ORDER 6-9).
    if (dest == TvDest.live) return const TvLiveScreen();
    if (dest == TvDest.search) return const TvSearchScreen();
    if (dest == TvDest.settings) return const TvSettingsScreen();
    return TvEmptyState(
      icon: dest.icon,
      title: dest.label,
      subtitle: 'Bientôt disponible. Cette section arrive très vite.',
    );
  }
}
