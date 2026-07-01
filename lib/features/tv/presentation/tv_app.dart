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
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/i18n/locale_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import '../data/display_settings.dart';
import 'tv_activation_screen.dart';
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_live_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_sports_screen.dart';
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
      listenable: Listenable.merge(
          <Listenable>[LocaleRepository.instance, DisplaySettings.instance]),
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
          // OVERSCAN : marge réglable de chaque côté (0 → 8 %) pour les TV qui
          // rognent les bords. Fraction identique en H et V → l'aspect reste
          // exact (pas de déformation). Défaut 0 % = comportement inchangé.
          final double ov = DisplaySettings.instance.overscanFraction;
          // TAILLE DU TEXTE : 1.0 (normal) ou 1.08 (grand, confort seniors).
          final double ts = DisplaySettings.instance.textScale;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: screen.width * ov,
              vertical: screen.height * ov,
            ),
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(designW, designH),
                textScaler: TextScaler.linear(ts),
              ),
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(width: designW, height: designH, child: child),
              ),
            ),
          );
        },
        home: const RestartWidget(child: TvGate()),
      ),
    );
  }
}

/// Permet un « redémarrage » logiciel de l'app : on change la clé du
/// sous-arbre → tout est reconstruit (initState relancés) → les chaînes /
/// la source / l'abonnement sont re-téléchargés. Réel rechargement sans
/// que le client ait à fermer puis rouvrir (qui ne rafraîchissait pas).
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() {
    // Re-synchronise explicitement (au cas où les écrans étaient déjà montés).
    SubscriptionState.instance.syncWithBackend();
    RemoteSourceRepository.sync();
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Dialogue Back/Exit : Continuer / Redémarrer / Quitter. Renvoie
/// 'restart', 'quit', ou null (continuer). Navigable à la télécommande.
Future<String?> showExitDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (BuildContext ctx) => const _ExitDialog(),
  );
}

class _ExitDialog extends StatelessWidget {
  const _ExitDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.l10n.tvQuitTitle,
                textAlign: TextAlign.center,
                style: TvTokens.display(28, color: TvTokens.text)),
            const SizedBox(height: 10),
            Text(context.l10n.tvQuitMessage,
                textAlign: TextAlign.center,
                style: TvTokens.ui(15, color: TvTokens.mutedDim)),
            const SizedBox(height: 26),
            _DialogBtn(
              icon: Icons.play_arrow_rounded,
              label: context.l10n.tvStay,
              autofocus: true,
              primary: true,
              onSelect: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 10),
            _DialogBtn(
              icon: Icons.refresh_rounded,
              label: context.l10n.tvRestart,
              onSelect: () => Navigator.of(context).pop('restart'),
            ),
            const SizedBox(height: 10),
            _DialogBtn(
              icon: Icons.power_settings_new_rounded,
              label: context.l10n.tvQuit,
              onSelect: () => Navigator.of(context).pop('quit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (primary ? TvTokens.goldBright : TvTokens.text);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.gold
                : (primary ? TvTokens.sel : Colors.transparent),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 10),
              Text(label,
                  style: TvTokens.ui(18, weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
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
    // VERROU « après 7 jours, paiement obligatoire » : si le SERVEUR a tranché
    // que l'accès est fini (essai expiré) ou coupé (gelé / banni), on BLOQUE —
    // MÊME si des chaînes sont déjà en cache. Sans ça, un client ayant chargé
    // sa source pendant l'essai continuerait à regarder GRATUITEMENT après les
    // 7 jours (les chaînes restaient en base locale). C'est la fuite à fermer.
    final bool mustBlock = s == SubscriptionStatus.trialExpired ||
        s == SubscriptionStatus.frozen ||
        s == SubscriptionStatus.banned;
    final bool hasOwnList =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    // `hasOwnList` n'ouvre l'accueil QUE si le statut n'est PAS bloquant. Cas
    // d'usage : statut INCONNU (serveur injoignable) → on ne verrouille pas un
    // client légitime sur une coupure réseau ; le verrou serveur reprend la
    // main dès que la connexion revient (et device-source ne livre plus la
    // source une fois l'essai expiré).
    final bool showHome = active || (hasOwnList && !mustBlock);
    final Widget home = showHome
        ? const TvHomeScreen()
        : const TvShell(child: TvActivationScreen());
    // Retour : sur l'ACCUEIL, c'est TvHomeScreen qui gère (contenu → menu →
    // boîte Quitter au dernier niveau). Ce PopScope racine (même route) ne
    // garde donc la boîte QUE pour l'écran d'activation ; sinon il laisse
    // faire l'accueil (sans ça, la boîte s'afficherait à chaque Retour).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        if (showHome) return; // géré par TvHomeScreen
        final String? action = await showExitDialog(context);
        if (!context.mounted) return;
        if (action == 'restart') {
          RestartWidget.restart(context);
        } else if (action == 'quit') {
          await SystemNavigator.pop();
        }
      },
      child: home,
    );
  }
}

/// Destinations de la navigation principale (buckets §8 home).
enum TvDest { live, news, films, series, guide, recordings, search, settings }

extension on TvDest {
  // Libellé traduit selon la langue active (context.l10n).
  String label(BuildContext context) {
    switch (this) {
      case TvDest.live:
        return context.l10n.tvNavLive;
      case TvDest.news:
        return 'Actu';
      case TvDest.films:
        return context.l10n.tvNavFilms;
      case TvDest.series:
        return context.l10n.tvNavSeries;
      case TvDest.guide:
        return context.l10n.tvNavGuide;
      case TvDest.recordings:
        return 'Enregistrements';
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
      case TvDest.news:
        return Icons.sports_soccer_rounded;
      case TvDest.films:
        return Icons.movie_rounded;
      case TvDest.series:
        return Icons.video_library_rounded;
      case TvDest.guide:
        return Icons.grid_view_rounded;
      case TvDest.recordings:
        return Icons.fiber_dvr_rounded;
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

  // Cible « Retour » : node posé sur l'item de menu sélectionné, pour y
  // ramener le focus depuis le contenu. `_railHasFocus` dit si le focus est
  // ACTUELLEMENT quelque part sur le menu de gauche.
  final FocusNode _railFocus = FocusNode(debugLabel: 'navRailSelected');
  bool _railHasFocus = false;

  @override
  void dispose() {
    _railFocus.dispose();
    super.dispose();
  }

  // RETOUR (n'importe quelle télécommande) :
  //   - depuis le CONTENU  → on ramène le focus au menu de gauche (vraie
  //     navigation arrière), PAS de pop-up.
  //   - déjà sur le MENU   → c'est le dernier niveau : on propose Quitter /
  //     Redémarrer (la boîte n'apparaît donc qu'au bout, pas à chaque Retour).
  Future<void> _onBack() async {
    if (!_railHasFocus) {
      _railFocus.requestFocus();
      return;
    }
    final String? action = await showExitDialog(context);
    if (!mounted) return;
    if (action == 'restart') {
      RestartWidget.restart(context);
    } else if (action == 'quit') {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        _onBack();
      },
      child: TvShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ----- BARRE HAUTE : marque (gauche) + contexte + MENU COMPACT (droite)
            //  Le menu de navigation est désormais COMPACT EN HAUT À DROITE : la
            //  grande colonne de gauche est libérée pour la LISTE des chaînes
            //  (lisibilité seniors). Le Focus englobant (non focusable) suit
            //  `_railHasFocus` (cible « Retour » = menu) sans piéger la
            //  navigation directionnelle.
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (bool f) {
                if (f != _railHasFocus) {
                  setState(() => _railHasFocus = f);
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  TvLogo(width: 92),
                  const SizedBox(width: 18),
                  const Expanded(child: _HomeHeader()),
                  const SizedBox(width: 18),
                  _CompactNavBar(
                    selected: _selected,
                    selectedFocusNode: _railFocus,
                    onSelect: (TvDest d) => setState(() => _selected = d),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ----- Panneau de contenu (PLEINE LARGEUR sous la barre) -----
            Expanded(child: _ContentPanel(dest: _selected)),
          ],
        ),
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
    // Jour de la semaine traduit dans la langue active (intl), p. ex.
    // « Lunes » en espagnol, « måndag » en suédois, « الاثنين » en arabe.
    final String localeName = Localizations.localeOf(context).toString();
    final String weekday =
        toBeginningOfSentenceCase(DateFormat.EEEE(localeName).format(_now)) ?? '';
    // UN SEUL bloc contexte en haut à gauche : salut + (ville · temp météo ·
    // jour · heure) sur 2 lignes. L'heure isolée en haut à droite est retirée.
    final String temp =
        (g != null && g.tempC != null) ? '${g.tempC!.round()}° ${g.emoji}' : '';
    final String dayTime = '$weekday · $_time';
    // ÉPURÉ (réf. design) : plus de « Bonjour 👋 ». Un simple cluster
    // ville · météo · jour · heure, DISCRET, aligné EN HAUT À DROITE.
    return Align(
      alignment: Alignment.centerRight,
      child: Text.rich(
        TextSpan(
          style: TvTokens.ui(18, color: TvTokens.mutedDim),
          children: <InlineSpan>[
            if (g != null && g.city.isNotEmpty) ...<InlineSpan>[
              TextSpan(
                  text: g.city,
                  style: TvTokens.ui(18,
                      weight: FontWeight.w600, color: TvTokens.muted)),
              const TextSpan(text: '   ·   '),
            ],
            if (temp.isNotEmpty) TextSpan(text: '$temp   ·   '),
            TextSpan(text: dayTime),
          ],
        ),
      ),
    );
  }
}
/// Menu de navigation COMPACT (barre horizontale, en HAUT À DROITE). Remplace
/// l'ancien rail vertical de gauche : la grande colonne de gauche est désormais
/// dédiée à la LISTE des chaînes (lisibilité seniors). Routing INCHANGÉ.
class _CompactNavBar extends StatelessWidget {
  const _CompactNavBar({
    required this.selected,
    required this.onSelect,
    this.selectedFocusNode,
  });

  final TvDest selected;
  final ValueChanged<TvDest> onSelect;
  final FocusNode? selectedFocusNode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < TvDest.values.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          _CompactNavItem(
            dest: TvDest.values[i],
            selected: TvDest.values[i] == selected,
            // L'item sélectionné porte le node « Retour » (cible du focus quand
            // on revient depuis le contenu).
            focusNode:
                TvDest.values[i] == selected ? selectedFocusNode : null,
            onSelect: () => onSelect(TvDest.values[i]),
          ),
        ],
      ],
    );
  }
}

class _CompactNavItem extends StatelessWidget {
  const _CompactNavItem({
    required this.dest,
    required this.selected,
    required this.onSelect,
    this.focusNode,
  });

  final TvDest dest;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      focusNode: focusNode,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        // Maison Noir : fond `--sel` + or au focus/actif ; bordure or si actif.
        final bool hl = focused || selected;
        final Color fg = hl ? TvTokens.goldBright : TvTokens.muted;
        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hl ? TvTokens.sel : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            border:
                selected ? Border.all(color: TvTokens.gold, width: 1) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(dest.icon, color: fg, size: 22),
              // Libellé affiché pour l'item ACTIF ou FOCUS (repère clair au D-pad
              // pour les seniors) ; les autres restent en icône seule (compact).
              if (hl) ...<Widget>[
                const SizedBox(width: 9),
                Text(
                  dest.label(context),
                  maxLines: 1,
                  softWrap: false,
                  style: TvTokens.ui(15, weight: FontWeight.w600, color: fg),
                ),
              ],
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
    if (dest == TvDest.news) return const TvSportsScreen();
    if (dest == TvDest.recordings) return const TvRecordingsScreen();
    if (dest == TvDest.guide) return const TvGuideGridScreen();
    if (dest == TvDest.films) return const TvFilmsScreen();
    if (dest == TvDest.series) return const TvSeriesScreen();
    if (dest == TvDest.search) return const TvSearchScreen();
    if (dest == TvDest.settings) return const TvSettingsScreen();
    return TvEmptyState(
      icon: dest.icon,
      title: dest.label(context),
      subtitle: context.l10n.tvComingSoon,
    );
  }
}
