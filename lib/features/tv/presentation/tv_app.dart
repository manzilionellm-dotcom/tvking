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
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/i18n/locale_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
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

/// Largeur LOGIQUE de référence du design TV. Toute l'app est rendue comme
/// si l'écran faisait cette largeur, puis mise à l'échelle vers l'écran réel
/// (cf. `MaterialApp.builder`). 1280 = canevas 10-foot standard (720p).
const double kTvDesignWidth = 1280;

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
    // On écoute LocaleRepository : `locale == null` => l'app SUIT la langue
    // de la TV (Android system locale). Si la télé est en espagnol, l'app
    // s'affiche en espagnol toute seule. Un changement manuel (Réglages)
    // reconstruit l'app via ce ListenableBuilder.
    return ListenableBuilder(
      listenable: LocaleRepository.instance,
      builder: (BuildContext context, _) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        // --- Internationalisation (8 langues, RTL auto pour l'arabe) ---
        locale: LocaleRepository.instance.locale, // null = langue de la TV
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: base.copyWith(
          // Police par défaut = Inter (Maison Noir) sur TOUT le texte.
          textTheme: GoogleFonts.interTextTheme(base.textTheme)
              .apply(bodyColor: TvTokens.text, displayColor: TvTokens.text),
          // Coupe TOUT effet tactile (hover/splash souris) — D-pad only.
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
        ),
        // CANEVAS TV FIXE : on rend TOUTE l'app comme un écran logique de
        // largeur `kTvDesignWidth`, puis on met à l'échelle uniforme vers
        // l'écran réel. Beaucoup de box Android TV / Fire TV rapportent une
        // résolution logique trop petite (ex. 960×540) → l'UI paraît
        // « zoomée ». Avec ce canevas fixe, l'app a TOUJOURS la même taille
        // relative, quelle que soit la TV. On neutralise aussi le textScale
        // système (certaines box le poussent à 1,3-1,5).
        builder: (BuildContext context, Widget? child) {
          final MediaQueryData mq = MediaQuery.of(context);
          final Size screen = mq.size;
          if (child == null || screen.width <= 0 || screen.height <= 0) {
            return child ?? const SizedBox.shrink();
          }
          const double designW = kTvDesignWidth;
          final double designH = designW * screen.height / screen.width;
          return MediaQuery(
            data: mq.copyWith(
              size: Size(designW, designH),
              textScaler: TextScaler.noScaling,
            ),
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(width: designW, height: designH, child: child),
            ),
          );
        },
        home: const TvGate(),
      ),
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
    final SubscriptionStatus s = SubscriptionState.instance.status;
    // L'app s'ouvre dès que l'appareil a un ACCÈS valide : abonnement PAYÉ
    // OU ESSAI EN COURS. Le revendeur peut activer un essai gratuit (Test
    // 24 h / 48 h / 7 j) depuis le panel → la TV doit se débloquer pareil,
    // pas seulement pour un abonnement payant. Ou si le client a apporté sa
    // propre liste (Xtream).
    final bool active = s == SubscriptionStatus.paid ||
        s == SubscriptionStatus.trialActive;
    final bool hasOwnList =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    if (active || hasOwnList) return const TvHomeScreen();
    return const TvShell(child: TvActivationScreen());
  }
}

/// Destinations de la navigation principale (buckets §8 home).
enum TvDest { live, films, series, guide, search, settings }

extension on TvDest {
  // Libellé traduit selon la langue active (context.l10n).
  String label(BuildContext context) {
    switch (this) {
      case TvDest.live:
        return context.l10n.tvNavLive;
      case TvDest.films:
        return context.l10n.tvNavFilms;
      case TvDest.series:
        return context.l10n.tvNavSeries;
      case TvDest.guide:
        return context.l10n.tvNavGuide;
      case TvDest.search:
        return context.l10n.tvNavSearch;
      case TvDest.settings:
        return context.l10n.tvNavSettings;
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

  @override
  Widget build(BuildContext context) {
    final Greeting? g = _g;
    final String weather = (g != null && g.tempC != null)
        ? ' · ${g.tempC!.round()}°C ${g.emoji}'
        : '';
    // Jour de la semaine traduit dans la langue active (intl), p. ex.
    // « Lunes » en espagnol, « måndag » en suédois, « الاثنين » en arabe.
    final String localeName = Localizations.localeOf(context).toString();
    final String weekday =
        toBeginningOfSentenceCase(DateFormat.EEEE(localeName).format(_now)) ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${context.l10n.tvHello} 👋',
                style: TvTokens.ui(30, weight: FontWeight.w600, color: TvTokens.text)),
            if (g != null && g.city.isNotEmpty)
              Text.rich(TextSpan(children: <InlineSpan>[
                TextSpan(text: g.city, style: TvTokens.ui(TvDimens.titleS, weight: FontWeight.w600, color: TvTokens.gold)),
                TextSpan(text: weather, style: TvTokens.ui(TvDimens.titleS, color: TvTokens.muted)),
              ])),
          ],
        ),
        const Spacer(),
        Text.rich(TextSpan(children: <InlineSpan>[
          TextSpan(text: weekday, style: TvTokens.ui(TvDimens.title, weight: FontWeight.w600, color: TvTokens.text)),
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
              Text(dest.label(context),
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
      title: dest.label(context),
      subtitle: context.l10n.tvComingSoon,
    );
  }
}
