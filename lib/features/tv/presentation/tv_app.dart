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
import '../../../core/theme/accent_controller.dart';
import '../../../core/update/update_prompt.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../../core/realtime/admin_message_banner.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import '../data/display_settings.dart';
import 'tv_activation_screen.dart';
import 'tv_screensaver.dart';
import 'tv_components.dart';
import 'tv_diagnostic_screen.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_live_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_sports_screen.dart';
import '../../sports/data/sports_repository.dart';
import '../../sports/domain/sport_models.dart';
import '../core/tv_ambience.dart';
import 'tv_care_nudge.dart';
import 'tv_night_comfort.dart';
import 'tv_profiles_screen.dart' show tvProfileDisplayName;
import 'tv_shell.dart';
import 'tv_who_watching_screen.dart';

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
      listenable: Listenable.merge(<Listenable>[
        LocaleRepository.instance,
        DisplaySettings.instance,
        // Thème d'accent (119 couleurs premium + mode immersif) : tout
        // changement recolore instantanément l'UI TV, comme sur mobile.
        AccentController.instance,
      ]),
      builder: (BuildContext context, _) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        // --- Internationalisation (8 langues, RTL auto pour l'arabe) ---
        locale: LocaleRepository.instance.locale, // null = langue de la TV
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // RÉSOLUTION DE LANGUE — CORRIGÉE. Sans ça, quand la TV est réglée
        // dans une langue qu'on ne connaît pas, Flutter retombe sur la
        // PREMIÈRE langue de la liste générée… qui pouvait être l'arabe →
        // « tout le monde en arabe ». On impose la bonne logique :
        //   1) choix explicite de l'utilisateur (Réglages) → prioritaire ;
        //   2) langue de la TV si on la supporte (match par code langue,
        //      p.ex. en_US → en, ar_MA → ar) ;
        //   3) repli SÛR = ANGLAIS (jamais l'arabe par défaut).
        localeResolutionCallback:
            (Locale? device, Iterable<Locale> supported) {
          final Locale? forced = LocaleRepository.instance.locale;
          if (forced != null) return forced;
          if (device != null) {
            for (final Locale s in supported) {
              if (s.languageCode == device.languageCode) return s;
            }
          }
          return const Locale('en');
        },
        theme: base.copyWith(
          // Police par défaut = Inter (Maison Noir) sur TOUT le texte.
          textTheme: GoogleFonts.interTextTheme(base.textTheme)
              .apply(bodyColor: TvTokens.text, displayColor: TvTokens.text),
          // Coupe TOUT effet tactile (hover/splash souris) — D-pad only.
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          // TRANSITIONS CINÉMA (réf. Apple TV+) : chaque changement d'écran
          // est un fondu + micro-zoom (0.98 → 1) décéléré — fluide et
          // GPU-léger (opacity + scale uniquement), au lieu du slide
          // Android par défaut qui fait « téléphone ».
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: _TvFadeLiftTransitionsBuilder(),
              TargetPlatform.linux: _TvFadeLiftTransitionsBuilder(),
              TargetPlatform.windows: _TvFadeLiftTransitionsBuilder(),
              TargetPlatform.macOS: _TvFadeLiftTransitionsBuilder(),
            },
          ),
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
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Padding(
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
                    child:
                        SizedBox(width: designW, height: designH, child: child),
                  ),
                ),
              ),
              // « NUIT ROYALE » : voile ambré de confort nocturne AU-DESSUS de
              // toute l'app (lecteur inclus). IgnorePointer → zéro impact sur
              // le D-pad/focus. Voir tv_night_comfort.dart.
              const TvNightComfortOverlay(),
              // « PENSE À TOI » : le mot doux après 3 h d'affilée (12 s, puis
              // s'efface). IgnorePointer aussi. Voir tv_care_nudge.dart.
              const TvCareNudge(),
              // MESSAGE ADMIN temps réel (WebSocket) : bannière en haut,
              // au-dessus de toute l'app (lecteur inclus). Invisible tant
              // qu'il n'y a rien (SizedBox.shrink → aucun nœud de focus,
              // donc AUCUN impact D-pad hors affichage). Auto-dismiss.
              const Align(
                alignment: Alignment.topCenter,
                child: SafeArea(child: AdminMessageBanner()),
              ),
            ],
          );
        },
        home: const RestartWidget(child: TvGate()),
      ),
    );
  }
}

/// Transition d'écran « cinéma » : fondu + micro-zoom décéléré. Le nouvel
/// écran se POSE (0.984 → 1.0) au lieu de glisser — signature visuelle
/// des interfaces TV haut de gamme. Coût GPU minimal (opacity + transform).
class _TvFadeLiftTransitionsBuilder extends PageTransitionsBuilder {
  const _TvFadeLiftTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final CurvedAnimation curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.984, end: 1.0).animate(curved),
        child: child,
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

  // MISE À JOUR IN-APP (sideload) : la box n'a PAS de Play Store — sans ce
  // branchement, une box allumée en continu ne se mettait JAMAIS à jour
  // (le revendeur devait re-sideloader à la main). On vérifie 30 s après
  // l'ouverture (laisser le boot respirer), puis toutes les 12 h (box
  // always-on). `maybePromptUpdate` est fail-open : rien de neuf ou réseau
  // KO → il ne se passe rien, jamais de crash. Le dialogue standard est
  // pilotable au D-pad (boutons focusables) sur toutes les télécommandes.
  Timer? _updateKick;
  Timer? _updateTick;

  // « Qui regarde ? » (façon Netflix) : montré UNE fois par ouverture d'app,
  // AVANT l'accueil, quand la famille a plusieurs profils. Une fois le profil
  // choisi (ou s'il n'y a qu'un profil), on file directement à l'accueil.
  bool _profileChosen = false;

  @override
  void initState() {
    super.initState();
    SubscriptionState.instance.addListener(_onChange);
    ProfilesRepository.instance.addListener(_onChange);
    _sub = PlaylistRepository.instance.channelsStream.listen((_) => _onChange());
    _updateKick = Timer(const Duration(seconds: 30), _checkUpdate);
    _updateTick =
        Timer.periodic(const Duration(hours: 12), (_) => _checkUpdate());
  }

  void _checkUpdate() {
    if (!mounted) return;
    unawaited(maybePromptUpdate(context));
  }

  @override
  void dispose() {
    SubscriptionState.instance.removeListener(_onChange);
    ProfilesRepository.instance.removeListener(_onChange);
    _sub?.cancel();
    _updateKick?.cancel();
    _updateTick?.cancel();
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
    // « Qui regarde ? » : si l'accès est ouvert, que la famille a PLUSIEURS
    // profils et qu'on n'a pas encore choisi cette session → on présente la
    // grille d'avatars AVANT l'accueil (exactement comme Netflix au démarrage).
    final bool needProfilePick = showHome &&
        !_profileChosen &&
        ProfilesRepository.instance.isLoaded &&
        ProfilesRepository.instance.profiles.length > 1;
    // VERROU : dès que l'ACCUEIL s'affiche, le choix de profil est considéré
    // FAIT pour cette session. Sans ça, un changement tardif du dépôt profils
    // (chargement qui finit après le 1er rendu, création d'un 2e profil depuis
    // l'écran Profils…) reconstruisait TvGate et REMPLAÇAIT l'accueil par
    // « Qui regarde ? » en pleine session — perçu comme un bug. Netflix ne
    // montre cet écran QU'AU LANCEMENT ; ensuite on en change via la pastille.
    if (showHome && !needProfilePick) _profileChosen = true;
    final Widget home = !showHome
        ? const TvShell(child: TvActivationScreen())
        : needProfilePick
            ? TvShell(
                child: TvWhoWatchingScreen(
                  onPicked: () => setState(() => _profileChosen = true),
                ),
              )
            : const TvHomeScreen();
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

/// Univers d'AMBIANCE associé à chaque destination : Films → lumière de
/// projecteur, Séries → nuit indigo, Actu/Sport → pelouse nocturne, tout
/// le reste → or Maison Noir. Voir core/tv_ambience.dart.
TvAmbienceKind _ambienceFor(TvDest d) {
  switch (d) {
    case TvDest.films:
      return TvAmbienceKind.cinema;
    case TvDest.series:
      return TvAmbienceKind.serie;
    case TvDest.news:
      return TvAmbienceKind.sport;
    case TvDest.live:
    case TvDest.guide:
    case TvDest.recordings:
    case TvDest.search:
    case TvDest.settings:
      return TvAmbienceKind.maison;
  }
}

extension on TvDest {
  // Libellé traduit selon la langue active (context.l10n).
  String label(BuildContext context) {
    switch (this) {
      case TvDest.live:
        return context.l10n.tvNavLive;
      case TvDest.news:
        return context.l10n.tvNavNews;
      case TvDest.films:
        return context.l10n.tvNavFilms;
      case TvDest.series:
        return context.l10n.tvNavSeries;
      case TvDest.guide:
        return context.l10n.tvNavGuide;
      case TvDest.recordings:
        return context.l10n.settingsRecordings;
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

  // Accès CACHÉ au diagnostic on-device : séquence D-pad HAUT-HAUT-BAS-BAS sur
  // l'accueil. Le Focus englobant ci-dessous OBSERVE les touches (il renvoie
  // toujours `ignored`) → la navigation directionnelle normale n'est jamais
  // perturbée. On garde seulement les 4 dernières flèches haut/bas.
  static const List<bool> _diagSeq = <bool>[true, true, false, false]; // H H B B
  final List<bool> _diagBuf = <bool>[];
  bool _diagOpen = false;

  @override
  void dispose() {
    _railFocus.dispose();
    super.dispose();
  }

  /// Observateur passif de touches (ne consomme RIEN). Détecte la séquence
  /// cachée et ouvre l'écran de diagnostic. Renvoie toujours `ignored`.
  KeyEventResult _onHomeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    final bool up =
        k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp;
    final bool down =
        k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown;
    if (!up && !down) {
      if (_diagBuf.isNotEmpty) _diagBuf.clear();
      return KeyEventResult.ignored;
    }
    _diagBuf.add(up);
    if (_diagBuf.length > _diagSeq.length) {
      _diagBuf.removeAt(0);
    }
    bool match = _diagBuf.length == _diagSeq.length;
    for (int i = 0; match && i < _diagSeq.length; i++) {
      if (_diagBuf[i] != _diagSeq[i]) match = false;
    }
    if (match) {
      _diagBuf.clear();
      _openDiagnostic();
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openDiagnostic() async {
    if (_diagOpen) return;
    _diagOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TvDiagnosticScreen()),
    );
    _diagOpen = false;
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
      // ÉCRAN DE VEILLE anti burn-in : ne s'arme QUE quand l'ACCUEIL est la
      // route visible (jamais pendant la lecture ni sur un autre écran).
      child: TvScreensaverWatcher(
        child: Focus(
        // OBSERVATEUR de touches uniquement : non focusable, hors traversée,
        // renvoie toujours `ignored` (cf. _onHomeKey). Sert seulement à capter
        // la séquence cachée HAUT-HAUT-BAS-BAS sans gêner la navigation.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onHomeKey,
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
                  const SizedBox(width: 16),
                  // ⚽ GRAND MATCH : le match (en direct ou à venir) d'une
                  // équipe favorite, affiché comme la météo. OK → univers
                  // Sport. Invisible si aucune équipe suivie / aucun match.
                  _MatchChip(onOpen: () {
                    setState(() => _selected = TvDest.news);
                    TvAmbience.instance.set(TvAmbienceKind.sport);
                  }),
                  const SizedBox(width: 12),
                  const _ProfileChip(),
                  const SizedBox(width: 12),
                  _CompactNavBar(
                    selected: _selected,
                    selectedFocusNode: _railFocus,
                    onSelect: (TvDest d) {
                      setState(() => _selected = d);
                      // AMBIANCE INTELLIGENTE : l'atmosphère de l'app suit
                      // l'univers ouvert (fondu lent dans TvShell).
                      TvAmbience.instance.set(_ambienceFor(d));
                    },
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
    // LE MOT DU CŒUR : un chiffre de météo, c'est froid — on y ajoute ce
    // qu'une grand-mère dirait. Tard le soir, on le murmure aussi. Un seul
    // mot à la fois, discret, dans le même gris que le reste.
    String heart = '';
    final int hh = _now.hour;
    final int wd = _now.weekday;
    if (hh >= 23 || hh < 5) {
      heart = context.l10n.tvHeartLate;
    } else if (g != null && g.tempC != null && g.tempC! <= 8) {
      heart = context.l10n.tvHeartCoverUp;
    } else if (g != null && g.tempC != null && g.tempC! >= 30) {
      heart = context.l10n.tvHeartDrink;
    } else if (hh >= 5 && hh < 10) {
      // SALUTATION VIVANTE : l'accueil sent le moment de la semaine.
      heart = context.l10n.tvHeartCoffee;
    } else if (wd == DateTime.friday && hh >= 18) {
      heart = context.l10n.tvHeartWeekend;
    } else if (wd == DateTime.sunday && hh >= 10 && hh < 20) {
      heart = context.l10n.tvHeartSunday;
    } else if (wd == DateTime.monday && hh < 12) {
      heart = context.l10n.tvHeartMonday;
    }
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
            // Le mot du cœur (« couvre-toi bien 🧣 », « il est tard 🌙 »…),
            // légèrement doré pour qu'on le sente sans qu'il crie.
            if (heart.isNotEmpty)
              TextSpan(
                  text: '   ·   $heart',
                  style: TvTokens.ui(18,
                      weight: FontWeight.w600, color: TvTokens.goldDeep)),
          ],
        ),
      ),
    );
  }
}
/// ⚽ Pastille « GRAND MATCH » (en haut de l'accueil, comme la météo) :
/// le match le plus pertinent des ÉQUIPES FAVORITES du client —
///   • EN DIRECT (point rouge + score s'il est connu), sinon
///   • le PROCHAIN match à venir (« France vs Belgique · 14/06 21:00 »).
/// OK → ouvre l'univers Sport (où l'on choisit aussi ses équipes).
/// INVISIBLE si aucune équipe suivie ou aucun match connu → zéro bruit.
class _MatchChip extends StatefulWidget {
  const _MatchChip({required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<_MatchChip> createState() => _MatchChipState();
}

class _MatchChipState extends State<_MatchChip> {
  StreamSubscription<void>? _changes;
  StreamSubscription<List<SportTeam>>? _favs;

  @override
  void initState() {
    super.initState();
    // Déjà initialisé au boot (main_tv) ; l'appel est idempotent.
    SportsRepository.instance.initialize();
    _changes = SportsRepository.instance.changesStream
        .listen((_) => _refresh());
    _favs = SportsRepository.instance.favoritesStream
        .listen((_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _changes?.cancel();
    _favs?.cancel();
    super.dispose();
  }

  /// Le match à afficher : un match EN COURS (départ il y a moins de 2 h 30)
  /// prime ; sinon le PROCHAIN à venir (le plus proche), sous 7 jours.
  (SportEvent, bool)? _pick() {
    final SportsRepository repo = SportsRepository.instance;
    final DateTime now = DateTime.now();
    SportEvent? live;
    SportEvent? upcoming;
    for (final SportTeam t in repo.favorites) {
      final SportsEvents ev = repo.eventsFor(t.id);
      for (final SportEvent e in <SportEvent>[...ev.next, ...ev.last]) {
        final DateTime? start = e.startsAt;
        if (start == null) continue;
        final Duration d = now.difference(start);
        if (!d.isNegative && d < const Duration(hours: 2, minutes: 30)) {
          live ??= e; // un match en cours suffit
        } else if (start.isAfter(now) &&
            start.difference(now) < const Duration(days: 7)) {
          if (upcoming == null || start.isBefore(upcoming.startsAt!)) {
            upcoming = e;
          }
        }
      }
    }
    if (live != null) return (live, true);
    if (upcoming != null) return (upcoming, false);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (SportEvent, bool)? picked = _pick();
    if (picked == null) return const SizedBox.shrink();
    final SportEvent e = picked.$1;
    final bool isLive = picked.$2;
    final String label = isLive
        ? (e.hasScore
            ? '${e.home} ${e.homeScore}–${e.awayScore} ${e.away}'
            : '${e.home} vs ${e.away}')
        : '${e.home} vs ${e.away} · ${e.whenLabel}';
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: widget.onOpen,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvTokens.goldBright
            : (isLive ? TvTokens.text : TvTokens.muted);
        return Container(
          height: 50,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            border: Border.all(
                color: focused
                    ? TvTokens.gold
                    : (isLive ? TvTokens.hairline : TvTokens.line),
                width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isLive) ...<Widget>[
                // Point rouge « EN DIRECT » (statique : sobre, pas de strobe).
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: TvTokens.live, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ] else ...<Widget>[
                const Text('⚽', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style:
                      TvTokens.ui(14.5, weight: FontWeight.w600, color: fg),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pastille du PROFIL ACTIF (en haut, façon Netflix). Un OK ouvre « Qui
/// regarde ? » pour changer de profil sans quitter l'accueil.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfilesRepository.instance,
      builder: (BuildContext context, _) {
        final TvProfile p = ProfilesRepository.instance.active;
        return TvFocusBuilder(
          scale: TvFocusScale.medium,
          onSelect: () => TvWhoWatchingScreen.show(context),
          builder: (BuildContext context, bool focused) {
            final Color fg = focused ? TvTokens.goldBright : TvTokens.muted;
            return Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: focused ? TvTokens.sel : Colors.transparent,
                borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
                border: focused
                    ? Border.all(color: TvTokens.gold, width: 1)
                    : Border.all(color: TvTokens.line, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(p.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    // Profil par défaut → nom localisé (« Famille »/« Family »…).
                    tvProfileDisplayName(context, p),
                    maxLines: 1,
                    softWrap: false,
                    style: TvTokens.ui(15, weight: FontWeight.w600, color: fg),
                  ),
                ],
              ),
            );
          },
        );
      },
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
