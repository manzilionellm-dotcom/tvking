// =========================================================
//  tv_hub_screen.dart — Accueil « lanceur » (grille de tuiles) pour la TV
// =========================================================
//  Disposition classique d'un lecteur de box, entièrement en design maison
//  (TvTokens + logo Zuno) :
//
//    ┌───────────────────────────────────────────────────────────┐
//    │ [logo]                                    📶  12:34  25/09  │  barre haut
//    │        ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐             │
//    │        │Direct│ │Films│ │Séries│ │Serveur│ │Régl.│          │  5 tuiles
//    │        └─────┘ └─────┘ └─────┘ └─────┘ └─────┘             │
//    │ CODE MK:..    Essai — 6 j    utilisateur@serveur           │  barre bas
//    └───────────────────────────────────────────────────────────┘
//
//  Chaque tuile ouvre un écran EXISTANT en pleine page (Retour = revenir au
//  lanceur). La licence (essai / payé / gelé / banni) est DÉCIDÉE par le panel
//  (via TvGate/SubscriptionState) et seulement AFFICHÉE ici — saisir une source
//  ne débloque pas l'accueil sans licence valide. Aucune couleur/taille en dur.
//
//  AU-DESSUS des tuiles, dès que la personne a déjà regardé quelque chose :
//  rappels qu'elle a posés, dernières chaînes, films entamés, favoris,
//  « populaire maintenant ». Rien ne se lance tout seul, sauf si elle a
//  choisi dans Réglages « Dernière chaîne » au démarrage (Retour = accueil).
// =========================================================
import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/trending_repository.dart';
import '../../channels/domain/channel.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../device/data/device_identity.dart';
import '../../epg/data/program_reminder_repository.dart';
import '../../epg/domain/program_reminder.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../security/data/parental_controls.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_content_refresh.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import '../data/home_shelves.dart';
import '../data/startup_preference.dart';
import 'tv_app.dart';
import 'tv_cinema_common.dart';
import 'tv_cinema_screen.dart';
import 'tv_components.dart';
import 'tv_diagnostic_screen.dart';
import 'tv_home_rails.dart';
import 'tv_live_screen.dart';
import 'tv_player_screen.dart';
import 'tv_profile_picker.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';
import 'tv_sources_screen.dart';

/// Les 5 tuiles de l'accueil, de gauche à droite.
enum _Tile { live, films, series, server, settings }

class TvHubScreen extends StatefulWidget {
  const TvHubScreen({super.key});
  @override
  State<TvHubScreen> createState() => _TvHubScreenState();
}

class _TvHubScreenState extends State<TvHubScreen> {
  // Barre du haut : heure/date (tick 20 s) + réseau.
  Timer? _clock;
  DateTime _now = DateTime.now();
  List<ConnectivityResult> _conn = const <ConnectivityResult>[];
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Barre du bas : MAC + serveur actif (rafraîchi quand les sources changent).
  String _mac = '…';
  StreamSubscription<List<Channel>>? _srcSub;
  String? _refreshNotice;

  // ----- « Source-push » DIRECT depuis le panel (décision du propriétaire) -----
  // Le revendeur assigne l'abonnement (Xtream/M3U) à la MAC dans le panel et
  // la box doit recevoir les chaînes SANS que le client ne fasse rien :
  //   • tant qu'on est sur l'accueil, on re-demande la source au panel toutes
  //     les 20 s (simple GET, dédupliqué côté repo → gratuit s'il n'y a rien
  //     de neuf) ;
  //   • dès que la licence passe à « actif » (activation dans le panel), on
  //     synchronise IMMÉDIATEMENT (sans attendre le tick) ;
  //   • quand les PREMIÈRES chaînes arrivent (0 → n) alors que l'accueil est
  //     au premier plan, on ouvre Direct tout seul : « le fil entre
  //     directement ». Une seule fois par session d'accueil, jamais si le
  //     client est déjà dans un autre écran.
  Timer? _sourcePoll;
  bool _hadChannels = false;
  bool _autoOpened = false;
  // Le choix de profil était devant l'accueil au moment où les
  // premières chaînes sont arrivées : on ouvrira Direct dès qu'il
  // se ferme. On ne bloque pas la chaîne, on attend juste que
  // l'écran du dessus parte.
  bool _pendingAutoOpen = false;
  bool _wasActive = false;
  static const Duration _kSourcePollEvery = Duration(seconds: 20);

  // Accès CACHÉ au diagnostic : séquence D-pad HAUT-HAUT-BAS-BAS.
  static const List<bool> _diagSeq = <bool>[true, true, false, false];
  final List<bool> _diagBuf = <bool>[];
  bool _diagOpen = false;

  // ----- Rangées « pour revenir » (voir home_shelves.dart) -----
  // On ne recalcule pas dans build() : un import de playlist peut émettre
  // souvent, et on ne veut qu'UN assemblage après une courte pause.
  List<Channel> _channels = const <Channel>[];
  Set<String> _favIds = <String>{};
  List<String> _recentIds = const <String>[];
  List<String> _trending = const <String>[];
  List<String> _popularIds = const <String>[];
  Greeting? _greeting;
  HomeShelfModel _shelves = const HomeShelfModel();
  HomeShelfKind? _initialShelf;
  bool _prefsReady = false;
  bool _resumedThisVisit = false;
  bool _pendingShelfFocus = true;
  // Première arrivée de chaînes AVANT que le réglage « au démarrage » soit lu :
  // on retient l'ouverture auto du Direct, pour ne pas ouvrir Direct PUIS
  // la dernière chaîne par-dessus.
  bool _deferredLiveOpen = false;
  int _popularGen = 0;
  Timer? _shelfDebounce;
  Timer? _popularDebounce;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<String>>? _trendSub;
  StreamSubscription<List<String>>? _recentSub;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    BlackBox.instance.info('SCREEN', 'Accueil');
    _hadChannels = PlaylistRepository.instance.currentChannels.isNotEmpty;
    _wasActive = _isActive(SubscriptionState.instance.status);
    SubscriptionState.instance.addListener(_onLicenseChange);
    // Pastille « Mise à jour… » (branche sécurité) : visible même avec les
    // rangées d'accueil. Elle ne bloque jamais l'ouverture d'une chaîne.
    _refreshNotice = TvContentRefresh.notice.value;
    TvContentRefresh.notice.addListener(_onRefreshNotice);
    _srcSub = PlaylistRepository.instance.channelsStream.listen(_onChannels);
    _initConnectivity();
    ProfileRepository.instance.addListener(_onProfileCatalog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOfferProfiles());
    });
    // Source-push direct : voir le commentaire du champ _sourcePoll.
    if (!BootGuard.instance.safeMode) {
      _sourcePoll = Timer.periodic(_kSourcePollEvery, (_) {
        if (mounted) RemoteSourceRepository.sync();
      });
    }
    // Ce qu'on a DÉJÀ en mémoire (le boot a chargé la playlist). Les dépôts
    // finissent de s'ouvrir dans _prepareEngagement, sans bloquer le 1er cadre.
    _channels = PlaylistRepository.instance.currentChannels;
    _favIds = FavoritesRepository.instance.current;
    _recentIds = RecentlyWatchedRepository.instance.current;
    _trending = TrendingRepository.instance.current;
    _rebuildShelves(notify: false);
    _favSub =
        FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      _favIds = ids;
      _scheduleShelves();
    });
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((List<String> ids) {
      _recentIds = ids;
      _scheduleShelves();
    });
    TrendingRepository.instance.start();
    _trendSub = TrendingRepository.instance.stream.listen((List<String> names) {
      if (listEquals(names, _trending)) return;
      _trending = names;
      _schedulePopular();
    });
    WatchProgressRepository.instance.addListener(_scheduleShelves);
    ProgramReminderRepository.instance.addListener(_scheduleShelves);
    ParentalControls.instance.kidsMode.addListener(_scheduleShelves);
    unawaited(_prepareEngagement());
  }

  static bool _isActive(SubscriptionStatus s) =>
      s == SubscriptionStatus.paid || s == SubscriptionStatus.trialActive;

  /// Licence changée : rafraîchit la barre du bas ET, si l'accès vient de
  /// s'ouvrir (activation faite dans le panel), va chercher la source TOUT DE
  /// SUITE — c'est le moment exact où le revendeur vient d'assigner l'abonnement.
  void _onLicenseChange() {
    final bool active = _isActive(SubscriptionState.instance.status);
    if (active && !_wasActive && !BootGuard.instance.safeMode) {
      RemoteSourceRepository.sync();
    }
    _wasActive = active;
    _onChange();
  }

  /// Chaînes changées : rafraîchit les rangées et, à la PREMIÈRE arrivée
  /// de chaînes (0 → n) pendant que l'accueil est visible, ouvre Direct
  /// — sauf si la personne a demandé la dernière chaîne (voir Réglages).
  void _onChannels(List<Channel> channels) {
    final bool has = channels.isNotEmpty;
    final bool firstArrival = has && !_hadChannels;
    _hadChannels = has;
    _channels = channels;
    _scheduleShelves();
    _schedulePopular();
    _onChange();
    if (!firstArrival || _autoOpened || !mounted) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    // Le choix de profil est devant : on n'ouvre pas une chaîne
    // par-dessus. On le fera quand il se ferme.
    if (route != null && !route.isCurrent) {
      if (StartupPickerSession.shown) _pendingAutoOpen = true;
      return;
    }
    if (!_prefsReady) {
      _deferredLiveOpen = true;
      return;
    }
    _openFreshSource();
  }

  /// Ouvre la dernière chaîne si l'option est cochée, sinon le Direct
  /// (comportement historique : « le fil entre directement » à la
  /// première source). Une seule fois. Ne vole jamais un écran.
  void _openFreshSource() {
    if (_autoOpened || !mounted) return;
    if (_tryResumeLast()) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _autoOpened = true;
    _openTile(_Tile.live);
  }

  void _onProfileCatalog() {
    if (!mounted) return;
    setState(() {});
    unawaited(_maybeOfferProfiles());
  }

  /// Choix de profil APRÈS le premier affichage. Un seul profil, ou
  /// l'option coupée : on ne montre rien, l'accueil s'ouvre comme avant.
  Future<void> _maybeOfferProfiles() async {
    if (!mounted || StartupPickerSession.shown) return;
    if (!ProfileRepository.instance.isReady) return;
    final bool offer = StartupProfilePolicy.shouldOffer(
      askOnStartup: ProfileRepository.instance.catalog.askOnStartup,
      profileCount: ProfileRepository.instance.catalog.profiles.length,
    );
    if (!offer) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    StartupPickerSession.shown = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const TvProfilePickerScreen()),
    );
    if (!mounted) return;
    _openLiveIfPending();
  }

  void _openLiveIfPending() {
    if (!_pendingAutoOpen || _autoOpened) return;
    if (!_prefsReady) return;
    if (PlaylistRepository.instance.currentChannels.isEmpty) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _pendingAutoOpen = false;
    _openFreshSource();
  }

  /// Vrai si on a vraiment lancé la dernière chaîne.
  bool _tryResumeLast() {
    _rebuildShelves(notify: false);
    if (!shouldResumeLastChannel(
      enabled: StartupPreference.instance.openLastChannel,
      alreadyResumedThisVisit: _resumedThisVisit,
      hasChannel: _shelves.lastChannel != null,
      safeMode: BootGuard.instance.safeMode,
    )) {
      return false;
    }
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final List<Channel> zap = List<Channel>.from(_shelves.resume);
    if (zap.isEmpty) return false;
    _resumedThisVisit = true;
    _autoOpened = true;
    _deferredLiveOpen = false;
    BlackBox.instance
        .info('ACCUEIL', 'reprise au démarrage : ${zap.first.name}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(channels: zap, startIndex: 0),
        ),
      );
    });
    return true;
  }

  Future<void> _prepareEngagement() async {
    await StartupPreference.instance.load();
    await RecentlyWatchedRepository.instance.initialize();
    await FavoritesRepository.instance.initialize();
    await ProgramReminderRepository.instance.load();
    await WatchProgressRepository.instance.load();
    if (!mounted) return;
    _prefsReady = true;
    _recentIds = RecentlyWatchedRepository.instance.current;
    _favIds = FavoritesRepository.instance.current;
    _rebuildShelves(notify: false);
    final bool resumed = _tryResumeLast();
    if (!resumed && _deferredLiveOpen && !_autoOpened) {
      final ModalRoute<Object?>? route = ModalRoute.of(context);
      if (route != null && !route.isCurrent && StartupPickerSession.shown) {
        _pendingAutoOpen = true;
      } else {
        _deferredLiveOpen = false;
        _openFreshSource();
      }
    }
    if (_pendingAutoOpen) _openLiveIfPending();
    if (mounted) setState(() {});
    _schedulePopular();
    final Greeting? g = await GreetingRepository.instance.fetch();
    if (!mounted || g == null) return;
    setState(() => _greeting = g);
  }

  void _scheduleShelves() {
    _shelfDebounce?.cancel();
    _shelfDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _rebuildShelves();
      _schedulePopular();
    });
  }

  void _schedulePopular() {
    _popularDebounce?.cancel();
    _popularDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_refreshPopular());
    });
  }

  /// Assemble les rangées à partir des listes déjà en mémoire.
  /// [notify] à false pendant initState / avant le premier cadre.
  void _rebuildShelves({bool notify = true}) {
    final bool kids = ParentalControls.instance.kidsMode.value;
    final Map<String, Channel> byId = indexChannelsById(_channels);
    bool hide(Channel c) => hiddenForKids(c);
    final bool Function(Channel)? kidsHide = kids ? hide : null;
    final int now = DateTime.now().millisecondsSinceEpoch;
    _shelves = HomeShelfModel(
      resume: channelsInIdOrder(_recentIds, byId, hide: kidsHide),
      favorites: favoriteChannels(_channels, _favIds, hide: kidsHide),
      popular: channelsInIdOrder(_popularIds, byId, hide: kidsHide),
      continueWatching: continueForHome(
        WatchProgressRepository.instance.continueWatching(),
        kidsMode: kids,
      ),
      reminders: ProgramReminderLog.forHome(
        ProgramReminderRepository.instance.current,
        now,
        channelStillThere: (String id) {
          final Channel? c = byId[id];
          if (c == null) return false;
          if (kids && hide(c)) return false;
          return true;
        },
      ),
    );
    if (_initialShelf == null && _shelves.hasAny) {
      _initialShelf = pickInitialShelf(
        hasSoonReminder: _shelves.reminders.any(
            (ProgramReminder r) => ProgramReminderLog.isSoon(r.startMs, now)),
        hasResume: _shelves.resume.isNotEmpty,
        hasContinue: _shelves.continueWatching.isNotEmpty,
        hasFavorites: _shelves.favorites.isNotEmpty,
        hasPopular: _shelves.popular.isNotEmpty,
      );
    }
    if (notify && mounted) setState(() {});
  }

  Future<void> _refreshPopular() async {
    final int gen = ++_popularGen;
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<String> ids = await resolvePopularIds(
      trendingNames: _trending,
      channels: _channels,
      kidsMode: kids,
    );
    if (!mounted || gen != _popularGen) return;
    _popularIds = ids;
    _rebuildShelves();
  }

  void _playShelf(List<Channel> shelf, int index) {
    if (index < 0 || index >= shelf.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: shelf, startIndex: index),
      ),
    );
  }

  void _playContinue(WatchEntry entry) {
    openVod(context, VodPlayItem.entry(entry));
  }

  /// Un rappel ouvre la CHAÎNE (on ne peut pas jouer une émission future).
  /// Le zap Haut/Bas reste sur les chaînes des rappels affichés.
  void _playReminder(ProgramReminder reminder) {
    final Map<String, Channel> byId = indexChannelsById(_channels);
    final Channel? target = byId[reminder.channelId];
    if (target == null) return;
    final List<Channel> shelf = <Channel>[
      for (final ProgramReminder item in _shelves.reminders)
        if (byId[item.channelId] != null) byId[item.channelId]!,
    ];
    final int index = shelf.indexWhere((Channel c) => c.id == target.id);
    _playShelf(
        shelf.isEmpty ? <Channel>[target] : shelf, index < 0 ? 0 : index);
  }

  String _hello(BuildContext context) {
    final String hello = switch (homeDayPart(_now.hour)) {
      HomeDayPart.morning => context.l10n.tvHelloMorning,
      HomeDayPart.afternoon => context.l10n.tvHelloAfternoon,
      HomeDayPart.evening => context.l10n.tvHelloEvening,
    };
    final Greeting? g = _greeting;
    final String city = g?.city.trim() ?? '';
    if (g == null || city.isEmpty) return hello;
    final String temp = g.tempC == null ? '' : '${g.tempC!.round()}°';
    final String place = temp.isEmpty ? city : '$temp $city';
    final String emoji = g.emoji;
    return emoji.isEmpty ? '$hello · $place' : '$hello · $emoji $place';
  }

  Future<void> _initConnectivity() async {
    try {
      _conn = await Connectivity().checkConnectivity();
      if (mounted) setState(() {});
      _connSub = Connectivity()
          .onConnectivityChanged
          .listen((List<ConnectivityResult> r) {
        if (mounted) setState(() => _conn = r);
      });
    } catch (_) {}
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _connSub?.cancel();
    _srcSub?.cancel();
    _sourcePoll?.cancel();
    _shelfDebounce?.cancel();
    _popularDebounce?.cancel();
    _favSub?.cancel();
    _trendSub?.cancel();
    _recentSub?.cancel();
    _popularGen++; // une réponse tardive ne touche plus cet écran
    TrendingRepository.instance.stop();
    WatchProgressRepository.instance.removeListener(_scheduleShelves);
    ProgramReminderRepository.instance.removeListener(_scheduleShelves);
    ParentalControls.instance.kidsMode.removeListener(_scheduleShelves);
    SubscriptionState.instance.removeListener(_onLicenseChange);
    TvContentRefresh.notice.removeListener(_onRefreshNotice);
    ProfileRepository.instance.removeListener(_onProfileCatalog);
    super.dispose();
  }

  void _onRefreshNotice() {
    if (!mounted) return;
    setState(() => _refreshNotice = TvContentRefresh.notice.value);
  }

  IconData get _netIcon {
    if (_conn.contains(ConnectivityResult.ethernet)) {
      return Icons.settings_ethernet_rounded;
    }
    if (_conn.contains(ConnectivityResult.wifi)) return Icons.wifi_rounded;
    if (_conn.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt_rounded;
    }
    return Icons.wifi_off_rounded;
  }

  ({String label, Color color}) _license(BuildContext context) {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (label: context.l10n.tvStatusPaid, color: TvTokens.success);
      case SubscriptionStatus.trialActive:
        return (
          label: context.l10n
              .tvStatusTrial(SubscriptionState.instance.trialDaysRemaining),
          color: TvTokens.accentBright,
        );
      case SubscriptionStatus.trialExpired:
        return (label: context.l10n.tvStatusTrialExpired, color: TvTokens.live);
      case SubscriptionStatus.frozen:
        return (label: context.l10n.tvStatusFrozen, color: TvTokens.live);
      case SubscriptionStatus.banned:
        return (label: context.l10n.tvStatusBanned, color: TvTokens.live);
      case SubscriptionStatus.unknown:
        return (label: '', color: TvTokens.mutedDim);
    }
  }

  String get _activeSource {
    try {
      final List<Playlist> all = PlaylistRepository.instance.currentPlaylists;
      if (all.isEmpty) return '';
      final Playlist p =
          all.firstWhere((Playlist x) => x.isActive, orElse: () => all.first);
      final String user = (p.xtreamUsername ?? '').trim();
      final String one = user.isEmpty ? p.name : '$user · ${p.name}';
      // Mode fusion (TV) : toutes les listes sont affichées ensemble → on
      // l'indique sobrement (« … +2 ») sans changer la mise en page.
      return all.length > 1 ? '$one +${all.length - 1}' : one;
    } catch (_) {
      return '';
    }
  }

  void _openTile(_Tile t) {
    Widget page;
    switch (t) {
      case _Tile.live:
        page = const TvLiveScreen();
      case _Tile.server:
        page = const TvSourcesScreen();
      case _Tile.settings:
        page = const TvSettingsScreen();
      case _Tile.films:
        page = const TvCinemaScreen(kind: CinemaKind.movie);
      case _Tile.series:
        page = const TvCinemaScreen(kind: CinemaKind.series);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TvShell(child: page)),
    );
  }

  Widget _tileRow(BuildContext context, {required bool compact}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _Tile.values.length; i++) ...<Widget>[
          _HubTile(
            meta: _tileMeta(context, _Tile.values[i]),
            autofocus: !compact && i == 0,
            compact: compact,
            onSelect: () => _openTile(_Tile.values[i]),
          ),
          if (i != _Tile.values.length - 1) SizedBox(width: compact ? 12 : 22),
        ],
      ],
    );
  }

  ({IconData icon, String label}) _tileMeta(BuildContext c, _Tile t) {
    switch (t) {
      case _Tile.live:
        return (icon: Icons.live_tv_rounded, label: c.l10n.tvNavLive);
      case _Tile.films:
        return (icon: Icons.movie_rounded, label: c.l10n.tvNavFilms);
      case _Tile.series:
        return (icon: Icons.video_library_rounded, label: c.l10n.tvNavSeries);
      case _Tile.server:
        return (icon: Icons.dns_rounded, label: c.l10n.tvNavServer);
      case _Tile.settings:
        return (icon: Icons.settings_rounded, label: c.l10n.tvNavSettings);
    }
  }

  Future<void> _onBack() async {
    final String? action = await showExitDialog(context);
    if (!mounted) return;
    if (action == 'restart') {
      RestartWidget.restart(context);
    } else if (action == 'quit') {
      // PC : SystemNavigator.pop ne ferme pas la fenêtre → sortie directe.
      if (!Platform.isAndroid) exit(0);
      await SystemNavigator.pop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    final bool up =
        k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp;
    final bool down = k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown;
    if (!up && !down) {
      if (_diagBuf.isNotEmpty) _diagBuf.clear();
      return KeyEventResult.ignored;
    }
    _diagBuf.add(up);
    if (_diagBuf.length > _diagSeq.length) _diagBuf.removeAt(0);
    bool match = _diagBuf.length == _diagSeq.length;
    for (int i = 0; match && i < _diagSeq.length; i++) {
      if (_diagBuf[i] != _diagSeq[i]) match = false;
    }
    if (match) {
      _diagBuf.clear();
      if (!_diagOpen) {
        _diagOpen = true;
        Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(
                builder: (_) => const TvDiagnosticScreen()))
            .then((_) => _diagOpen = false);
      }
    }
    return KeyEventResult.ignored;
  }

  String get _time =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Le focus automatique des rangées ne doit jouer qu'UNE fois (à leur
    // apparition). Le laisser à true réclamerait le focus à chaque cadre.
    if (_pendingShelfFocus && _shelves.hasAny) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingShelfFocus = false;
      });
    }
    final String localeName = Localizations.localeOf(context).toString();
    final String date = DateFormat('EEE d MMM', localeName).format(_now);
    final ({String label, Color color}) lic = _license(context);
    final String src = _activeSource;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _onBack();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: TvShell(
          // Fond PLEIN ÉCRAN (image de marque, cf. pubspec) + voile sombre pour
          // garder les textes lisibles, puis le contenu dans les marges TV.
          applySafeArea: false,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset('assets/branding/tv_hub_background.jpg',
                  fit: BoxFit.cover),
              DecoratedBox(
                  decoration: BoxDecoration(
                      color: TvTokens.bg.withValues(alpha: 0.35))),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: TvDimens.safeH, vertical: TvDimens.safeV),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ---------- BARRE DU HAUT ----------
                    Row(
                      children: <Widget>[
                        const TvLogo(width: 150),
                        const SizedBox(width: 18),
                        _ProfileChip(
                          onSelect: () {
                            StartupPickerSession.shown = true;
                            Navigator.of(context)
                                .push<bool>(MaterialPageRoute<bool>(
                                    builder: (_) =>
                                        const TvProfilePickerScreen()))
                                .then((_) => _openLiveIfPending());
                          },
                        ),
                        const Spacer(),
                        Icon(_netIcon, size: 22, color: TvTokens.muted),
                        const SizedBox(width: 16),
                        Text(_time,
                            style: TvTokens.display(22, color: TvTokens.text)),
                        const SizedBox(width: 12),
                        Text(date,
                            style: TvTokens.ui(15, color: TvTokens.mutedDim)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hello(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.display(TvDimens.title,
                          color: TvTokens.text),
                    ),
                    if (!_shelves.hasAny) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.tvHomeInvite,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TvTokens.ui(TvDimens.label, color: TvTokens.muted),
                      ),
                    ],
                    // ---------- RANGÉES + TUILES ----------
                    // Avec du contenu personnel, les rangées prennent la place et
                    // les tuiles se font plus petites en bas. Sans historique, les
                    // tuiles restent grandes et centrées (l'accueil d'origine).
                    Expanded(
                      child: _shelves.hasAny
                          ? Column(
                              children: <Widget>[
                                Expanded(
                                  child: TvHomeRails(
                                    model: _shelves,
                                    nowMs: _now.millisecondsSinceEpoch,
                                    initialShelf: _pendingShelfFocus
                                        ? _initialShelf
                                        : null,
                                    onPlayChannel: _playShelf,
                                    onPlayContinue: _playContinue,
                                    onPlayReminder: _playReminder,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _tileRow(context, compact: true),
                              ],
                            )
                          : Center(child: _tileRow(context, compact: false)),
                    ),
                    if (_refreshNotice != null && _refreshNotice!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _refreshNotice!,
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(14, color: TvTokens.live),
                        ),
                      ),
                    // ---------- BARRE DU BAS ----------
                    Row(
                      children: <Widget>[
                        Text('${context.l10n.tvActivationCodeLabel} : ',
                            style: TvTokens.ui(14, color: TvTokens.mutedDim)),
                        Text(_mac,
                            style: TvTokens.mono(16, color: TvTokens.accentBright)),
                        const Spacer(),
                        if (lic.label.isNotEmpty)
                          Text(lic.label,
                              style: TvTokens.ui(15,
                                  weight: FontWeight.w600, color: lic.color)),
                        if (src.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 18),
                          Text(src,
                              style: TvTokens.ui(14, color: TvTokens.mutedDim)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille du profil en cours, à côté du logo. OK ouvre le choix.
/// Pas d'autofocus : Direct reste la première tuile, le démarrage
/// ne change pas de geste.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.onSelect});
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final profile = ProfileRepository.instance.active;
    return TvFocusBuilder(
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(ProfileLooks.icon(profile),
                  size: 22,
                  color: focused ? TvTokens.onAccent : ProfileLooks.color(profile)),
              const SizedBox(width: 8),
              Text(profile.name,
                  style: TvTokens.ui(TvDimens.label,
                      weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// Une tuile carrée focusable (icône + libellé). Focus = fond braise + lueur.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.meta,
    required this.onSelect,
    this.autofocus = false,
    this.compact = false,
  });
  final ({IconData icon, String label}) meta;
  final VoidCallback onSelect;
  final bool autofocus;

  /// Vrai quand les rangées sont là : la tuile laisse la place au contenu.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double side = compact ? 124 : 190;
    final double icon = compact ? 36 : 64;
    final double gap = compact ? 8 : 18;
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: compact ? TvFocusScale.small : TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
                color: focused ? TvTokens.accent : TvTokens.line,
                width: focused ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(meta.icon,
                  size: icon,
                  color: focused ? TvTokens.onAccent : TvTokens.accent),
              SizedBox(height: gap),
              Text(meta.label,
                  style: TvTokens.ui(
                    compact ? TvDimens.label : TvDimens.titleS,
                    weight: FontWeight.w700,
                    color: fg,
                  )),
            ],
          ),
        );
      },
    );
  }
}
