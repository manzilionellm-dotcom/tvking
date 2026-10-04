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
import '../../epg/data/catchup_url_builder.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/data/program_reminder_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../epg/domain/program_reminder.dart';
import '../../followed/data/followed_flag.dart';
import '../../followed/data/followed_lead.dart';
import '../../followed/data/followed_log.dart';
import '../../followed/domain/show_clock.dart';
import '../../followed/domain/show_lines.dart';
import '../../followed/domain/show_taste.dart';
import '../../followed/presentation/show_banner.dart';
import '../../country_home/data/featured_repository.dart';
import '../../panel_board/data/panel_board_flags.dart';
import '../../panel_board/data/promo_banner_repository.dart';
import '../../panel_board/domain/panel_board.dart';
import '../../panel_board/presentation/tv_featured_card.dart';
import '../../panel_board/presentation/tv_panel_notice.dart';
import '../../panel_board/presentation/tv_promo_banner.dart';
import '../../simple_home/data/announcement_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import 'tv_phone_source_qr.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../box_extras/box_text.dart';
import '../../security/data/parental_controls.dart';
import '../../time_picks/data/time_pick_flag.dart';
import '../../time_picks/data/time_pick_log.dart';
import '../../subscription/data/remote_activation_watch.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/resume_zap.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_content_refresh.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';
import '../data/home_shelves.dart';
import '../data/startup_preference.dart';
import '../../voice/presentation/voice_navigation.dart';
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
  // null tant qu'on n'a pas lu la base : on n'affiche pas le QR
  // trop tôt (un client qui a déjà une source ne doit pas le voir
  // le temps du chargement). false = aucune playlist locale.
  bool? _hasLocalSource;
  StreamSubscription<List<Channel>>? _srcSub;
  String? _refreshNotice;

  // ----- « Source-push » DIRECT depuis le panel (décision du propriétaire) -----
  // Le revendeur assigne l'abonnement (Xtream/M3U) à la MAC dans le panel et
  // la box doit recevoir les chaînes SANS que le client ne fasse rien :
  //   • la veille unique (RemoteActivationWatch) lit le statut toutes
  //     les quelques secondes et ne télécharge les codes que si le
  //     panel a changé quelque chose ;
  //   • dès que la licence passe à « actif », on demande tout de suite
  //     une lecture (sans attendre le prochain délai) ;
  //   • quand les PREMIÈRES chaînes arrivent (0 → n) alors que l'accueil est
  //     au premier plan, on ouvre Direct tout seul : « le fil entre
  //     directement ». Une seule fois par session d'accueil, jamais si le
  //     client est déjà dans un autre écran.
  bool _hadChannels = false;
  bool _autoOpened = false;
  // Le choix de profil était devant l'accueil au moment où les
  // premières chaînes sont arrivées : on ouvrira Direct dès qu'il
  // se ferme. On ne bloque pas la chaîne, on attend juste que
  // l'écran du dessus parte.
  bool _pendingAutoOpen = false;
  bool _wasActive = false;

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
  List<String> _timePickIds = const <String>[];
  List<Channel> _timePicks = const <Channel>[];
  List<ShowCue> _showCards = const <ShowCue>[];
  ShowCue? _banner;
  bool _bannerRewind = false;
  List<GuideSlot> _guide = const <GuideSlot>[];
  int _guideAtMs = 0;
  int _showGen = 0;
  bool _showsOn = true;
  int _leadMin = kLeadDefault;
  Greeting? _greeting;
  // ----- Cartes venues du PANEL (voir panel_board.dart) -----
  // Une seule à la fois en tête des rangées ; l'émission suivie par la
  // personne (_banner) passe toujours devant. Rien ne se lance tout seul.
  Announcement? _notice;
  bool _noticeDismissed = false;
  Channel? _featuredChannel;
  String _featuredNote = '';
  PromoBanner? _promo;
  Channel? _promoChannel;
  String? _promoCounted; // dernière bannière comptée « montrée »
  int _panelTick = 0;
  // Deux compteurs séparés : une recherche de bannière ne doit pas
  // annuler la réponse en vol du favori du jour (et inversement).
  int _featuredGen = 0;
  int _promoGen = 0;
  Timer? _panelDebounce;
  bool _noticeOn = true;
  bool _featuredOn = true;
  bool _promoOn = true;
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
      if (!mounted) return;
      _now = DateTime.now();
      // Le texte « dans 4 minutes » se met à jour sans relire
      // le guide. La lecture du guide, elle, attend une minute.
      _replanShows();
      // Les cartes du panel tournent au même rythme (20 s).
      _panelTick++;
      _replanPanel();
      setState(() {});
      final int nowMs = _now.millisecondsSinceEpoch;
      if (_guideAtMs == 0 || nowMs - _guideAtMs >= 60000) {
        unawaited(_reloadGuide());
      }
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
    // Ce qu'on a DÉJÀ en mémoire (le boot a chargé la playlist). Les dépôts
    // finissent de s'ouvrir dans _prepareEngagement, sans bloquer le 1er cadre.
    _channels = PlaylistRepository.instance.currentChannels;
    // Déjà des chaînes en mémoire : une source est là, pas de QR.
    // Sinon on lit les playlists (une source peut exister avant
    // que ses chaînes soient chargées).
    if (_channels.isNotEmpty) {
      _hasLocalSource = true;
    } else {
      unawaited(_lookForLocalSource());
    }
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
    TimePickLog.instance.listenable.addListener(_onTimePicks);
    timePicksFlag.changes.addListener(_onTimeFlag);
    FollowedLog.instance.listenable.addListener(_onFollowed);
    followedFlag.changes.addListener(_onFollowedFlag);
    AnnouncementRepository.latest.addListener(_onNotice);
    FeaturedRepository.instance.addListener(_onFeatured);
    PromoBannerRepository.instance.addListener(_replanPanel);
    ParentalControls.instance.kidsMode.addListener(_replanPanel);
    panelNoticeFlag.changes.addListener(_onPanelFlags);
    featuredFlag.changes.addListener(_onPanelFlags);
    promoBannerFlag.changes.addListener(_onPanelFlags);
    unawaited(_prepareEngagement());
    unawaited(_preparePanelBoard());
  }

  // ---------------------------------------------------------------------
  //  Cartes du panel : annonce, favori du jour, bannières
  // ---------------------------------------------------------------------

  /// Lit les trois interrupteurs puis ouvre les dépôts (cache d'abord,
  /// réseau ensuite). Le canal « signal » les rafraîchira quand le panel
  /// publie ; l'accueil n'a qu'à écouter.
  Future<void> _preparePanelBoard() async {
    try {
      await Future.wait(<Future<void>>[
        panelNoticeFlag.load(),
        featuredFlag.load(),
        promoBannerFlag.load(),
      ]);
    } catch (_) {}
    if (!mounted) return;
    _readPanelFlags();
    if (_featuredOn) unawaited(FeaturedRepository.instance.initialize());
    if (_promoOn) unawaited(PromoBannerRepository.instance.initialize());
    if (_noticeOn) unawaited(AnnouncementRepository.fetchIfStale());
    unawaited(_onNotice());
    _onFeatured();
    _replanPanel();
  }

  void _readPanelFlags() {
    _noticeOn = panelNoticeFlag.value;
    _featuredOn = featuredFlag.value;
    _promoOn = promoBannerFlag.value;
  }

  void _onPanelFlags() {
    if (!mounted) return;
    _readPanelFlags();
    _onFeatured();
    _replanPanel();
  }

  /// L'annonce a changé (canal « signal » ou relecture) : on regarde si
  /// la personne l'a déjà fermée AVANT de l'afficher.
  Future<void> _onNotice() async {
    final Announcement? a = AnnouncementRepository.latest.value;
    bool dismissed = false;
    if (a != null) dismissed = await AnnouncementRepository.isDismissed(a.id);
    if (!mounted || a != AnnouncementRepository.latest.value) return;
    setState(() {
      _notice = a;
      _noticeDismissed = dismissed;
    });
  }

  bool get _noticeVisible =>
      _noticeOn &&
      _notice != null &&
      !_noticeDismissed &&
      noticeAllowed(
        kind: _notice!.kind,
        kidsMode: ParentalControls.instance.kidsMode.value,
      );

  Future<void> _seenNotice() async {
    final Announcement? a = _notice;
    if (a == null) return;
    BlackBox.instance.info('PANEL', 'annonce ${a.id} vue');
    setState(() => _noticeDismissed = true);
    await AnnouncementRepository.dismiss(a.id);
  }

  /// Le favori du jour est un NOM : on cherche la chaîne dans la liste
  /// (hors fil UI si elle est grosse). Liste changée → on recherche.
  void _onFeatured() {
    if (!mounted) return;
    final FeaturedRepository f = FeaturedRepository.instance;
    final int gen = ++_featuredGen;
    _featuredNote = f.note;
    if (!_featuredOn || !f.hasFeatured) {
      if (_featuredChannel != null) setState(() => _featuredChannel = null);
      return;
    }
    unawaited(findChannelByName(f.name, _channels).then((Channel? c) {
      if (!mounted || gen != _featuredGen) return;
      if (c?.id != _featuredChannel?.id) setState(() => _featuredChannel = c);
    }));
  }

  /// Quelle bannière maintenant (fenêtre, mode enfants, fermée, plafond
  /// du jour, rotation), et on la compte « montrée » si c'est bien elle
  /// qui est à l'écran (pas si l'émission suivie passe devant).
  void _replanPanel() {
    if (!mounted) return;
    final int nowMs = _now.millisecondsSinceEpoch;
    final PromoBannerRepository repo = PromoBannerRepository.instance;
    final List<PromoBanner> eligible = _promoOn
        ? eligiblePromos(
            banners: repo.banners,
            nowMs: nowMs,
            kidsMode: ParentalControls.instance.kidsMode.value,
            shownToday: repo.shownToday(_now),
            dismissed: repo.dismissedAt(nowMs),
          )
        : const <PromoBanner>[];
    final PromoBanner? next = rotatePromo(eligible, _panelTick);
    if (next?.id != _promo?.id) {
      _promo = next;
      _promoChannel = null;
      if (next != null && next.channel.isNotEmpty) {
        final int gen = ++_promoGen;
        unawaited(findChannelByName(next.channel, _channels).then((Channel? c) {
          if (!mounted || gen != _promoGen || _promo?.id != next.id) return;
          setState(() => _promoChannel = c);
        }));
      }
    }
    final HeaderCard card = _headerCard;
    if (card == HeaderCard.promo && next != null && next.id != _promoCounted) {
      _promoCounted = next.id;
      unawaited(repo.noteShown(next.id, now: _now));
    }
    setState(() {});
  }

  HeaderCard get _headerCard => pickHeaderCard(
        hasShow: _banner != null,
        hasNotice: _noticeVisible,
        hasPromo: _promo != null,
        hasFeatured: _featuredOn && _featuredChannel != null,
        tick: _panelTick,
      );

  void _closePromo() {
    final PromoBanner? b = _promo;
    if (b == null) return;
    BlackBox.instance.info('PANEL', 'bannière ${b.id} fermée');
    unawaited(PromoBannerRepository.instance.dismiss(b.id, now: _now));
  }

  void _watchPromo() {
    final Channel? c = _promoChannel;
    if (c == null) return;
    BlackBox.instance.info('PANEL', 'bannière ${_promo?.id} → chaîne');
    _playShelf(<Channel>[c], 0);
  }

  void _watchFeatured() {
    final Channel? c = _featuredChannel;
    if (c == null) return;
    BlackBox.instance.info('PANEL', 'favori du jour → chaîne');
    _playShelf(<Channel>[c], 0);
  }

  /// La carte en tête des rangées : une seule, choisie par
  /// [pickHeaderCard]. `null` = rien.
  Widget? _panelHeader(String lang) {
    switch (_headerCard) {
      case HeaderCard.show:
        return ShowBanner(
          cue: _banner!,
          languageCode: lang,
          canRewind: _bannerRewind,
          onWatch: () => _openShow(_banner!),
          onLive: () => _openShow(_banner!),
          onRewind: () => _openShow(_banner!, fromStart: true),
          onReplay: () => _openShow(_banner!, replay: true),
          onLater: _dismissBanner,
        );
      case HeaderCard.notice:
        return TvPanelNotice(notice: _notice!, onSeen: _seenNotice);
      case HeaderCard.promo:
        return TvPromoBanner(
          banner: _promo!,
          channelFound: _promoChannel != null,
          onWatch: _watchPromo,
          onClose: _closePromo,
        );
      case HeaderCard.featured:
        return TvFeaturedCard(
          channel: _featuredChannel!,
          note: _featuredNote,
          onWatch: _watchFeatured,
        );
      case HeaderCard.none:
        return null;
    }
  }

  static bool _isActive(SubscriptionStatus s) =>
      s == SubscriptionStatus.paid || s == SubscriptionStatus.trialActive;

  /// Licence changée : rafraîchit la barre du bas ET, si l'accès vient de
  /// s'ouvrir (activation faite dans le panel), va chercher la source TOUT DE
  /// SUITE — c'est le moment exact où le revendeur vient d'assigner l'abonnement.
  void _onLicenseChange() {
    final bool active = _isActive(SubscriptionState.instance.status);
    if (active && !_wasActive && !BootGuard.instance.safeMode) {
      RemoteActivationWatch.instance.nudge();
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
    if (has) {
      _hasLocalSource = true;
    } else if (_hasLocalSource == true) {
      // La dernière source vient d'être retirée : on revérifie,
      // et le QR revient si la base est vraiment vide.
      _hasLocalSource = null;
      unawaited(_lookForLocalSource());
    }
    _channels = channels;
    _scheduleShelves();
    _schedulePopular();
    // Le favori du jour et la chaîne d'une bannière se cherchent par nom
    // dans la liste : liste changée, on recherche — après une courte
    // pause, car un import émet souvent (même idée que _scheduleShelves).
    _panelDebounce?.cancel();
    _panelDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _onFeatured();
      final PromoBanner? promo = _promo;
      if (promo != null && promo.channel.isNotEmpty) {
        _promo = null;
        _replanPanel();
      }
    });
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
    // Dernière chaîne, mais Haut/Bas parcourent TOUTE la liste du client
    // (pas seulement les 8 chaînes « Reprendre »).
    final ResumeZap? plan = resumeZapList(
      PlaylistRepository.instance.currentChannels,
      _shelves.resume,
    );
    if (plan == null) return false;
    final List<Channel> zap = plan.channels;
    final int startIndex = plan.startIndex;
    _resumedThisVisit = true;
    _autoOpened = true;
    _deferredLiveOpen = false;
    BlackBox.instance
        .info('ACCUEIL', 'reprise au démarrage : ${zap.first.name}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(channels: zap, startIndex: startIndex),
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
    unawaited(_reloadTimePicks());
    unawaited(_reloadGuide());
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
    _timePicks = channelsInIdOrder(_timePickIds, byId, hide: kidsHide);
    if (notify && mounted) setState(() {});
  }

  void _onTimeFlag() {
    unawaited(_reloadTimePicks());
  }

  void _onTimePicks() {
    if (!mounted) return;
    if (!timePicksFlag.value) {
      if (_timePickIds.isEmpty) return;
      _timePickIds = const <String>[];
      _rebuildShelves();
      return;
    }
    _timePickIds = TimePickLog.instance.idsNow();
    _rebuildShelves();
  }

  /// La rangée n'existe que si l'interrupteur est allumé ET que
  /// CE créneau a déjà des chaînes. Sinon on laisse la liste vide :
  /// pas de repli sur « tout ce qui a été regardé ».
  Future<void> _reloadTimePicks() async {
    try {
      await timePicksFlag.load();
      if (!timePicksFlag.value) {
        _timePickIds = const <String>[];
      } else {
        await TimePickLog.instance.reload();
        _timePickIds = TimePickLog.instance.idsNow();
      }
    } catch (_) {
      _timePickIds = const <String>[];
    }
    if (mounted) _rebuildShelves();
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

  void _onFollowedFlag() {
    unawaited(_reloadGuide());
  }

  Set<String> _followedNow = <String>{};

  /// Le carnet a changé. On recalcule avec le guide DÉJÀ lu.
  /// S'il y a une émission suivie de plus, on relit le guide
  /// (une épingle ne doit pas attendre une minute).
  void _onFollowed() {
    if (!mounted) return;
    final Set<String> keys = followedKeys(FollowedLog.instance.book, _favIds);
    final bool changed =
        keys.length != _followedNow.length || !keys.containsAll(_followedNow);
    _followedNow = keys;
    if (changed) {
      _guideAtMs = 0;
      unawaited(_reloadGuide());
      return;
    }
    _replanShows();
    setState(() {});
  }

  void _replanShows() {
    if (!_showsOn) {
      _showCards = const <ShowCue>[];
      _banner = null;
      _bannerRewind = false;
      return;
    }
    final int now = _now.millisecondsSinceEpoch;
    final ShowPlan plan = planShows(
      nowMs: now,
      leadMinutes: _leadMin,
      programs: _guide,
      followed: followedKeys(FollowedLog.instance.book, _favIds),
      seen: FollowedLog.instance.seen,
    );
    _showCards = plan.row;
    if (_banner != null && cueStillCurrent(_banner!, now)) {
      _banner = _freshMinutes(_banner!, now);
    } else if (plan.banner != null) {
      final ShowCue next = plan.banner!;
      if (_banner == null || _banner!.alertKey != next.alertKey) {
        _banner = next;
        unawaited(FollowedLog.instance.markSeen(next.alertKey, nowMs: now));
      }
    } else {
      _banner = null;
    }
    _bannerRewind = _rewindReady(_banner);
  }

  ShowCue _freshMinutes(ShowCue cue, int now) {
    switch (cue.moment) {
      case ShowMoment.soon:
        final int delta = cue.startMs - now;
        final int minutes = delta <= 0 ? 1 : (delta / 60000).ceil();
        return cue.withMinutes(minutes);
      case ShowMoment.started:
      case ShowMoment.onAir:
        final int minutes = (now - cue.startMs) ~/ 60000;
        return cue.withMinutes(minutes < 1 ? 1 : minutes);
      case ShowMoment.finished:
        final int minutes = (now - cue.stopMs) ~/ 60000;
        return cue.withMinutes(minutes < 0 ? 0 : minutes);
    }
  }

  bool _rewindReady(ShowCue? cue) {
    if (cue == null || !cue.canRewind) return false;
    final Channel? channel = indexChannelsById(_channels)[cue.channelId];
    if (channel == null) return false;
    final String? url = CatchupUrlBuilder.build(
      channel: channel,
      program: EpgProgram(
        channelId: cue.channelId,
        startTime: cue.startMs,
        stopTime: cue.stopMs,
        title: cue.title,
      ),
    );
    return url != null && url.isNotEmpty;
  }

  /// Lit le guide au plus une fois par minute, et seulement
  /// s'il y a déjà une émission suivie. Guide vide ou base
  /// en erreur : liste vide, l'accueil continue.
  Future<void> _reloadGuide() async {
    final int gen = ++_showGen;
    try {
      await followedFlag.load();
      _showsOn = followedFlag.value;
      _leadMin = await FollowedLead.load();
      if (!_showsOn) {
        _guide = const <GuideSlot>[];
        if (gen == _showGen && mounted) {
          _replanShows();
          setState(() {});
        }
        return;
      }
      await FollowedLog.instance.reload();
      if (gen != _showGen || !mounted) return;
      final Set<String> keys = followedKeys(FollowedLog.instance.book, _favIds);
      if (keys.isEmpty) {
        _guide = const <GuideSlot>[];
        _guideAtMs = DateTime.now().millisecondsSinceEpoch;
        _replanShows();
        if (mounted) setState(() {});
        return;
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int from = now - 2 * 60 * 60 * 1000;
      final int to = now + kReplayHorizonMs;
      final List<EpgProgram> found = <EpgProgram>[];
      final Set<String> seenProg = <String>{};
      void take(List<EpgProgram> list) {
        for (final EpgProgram program in list) {
          final String id =
              '${program.channelId}@${program.startTime}@${program.title}';
          if (seenProg.add(id)) found.add(program);
        }
      }

      try {
        take(await EpgRepository.instance.programsOverlapping(
          from,
          to,
          limit: 800,
        ));
      } catch (_) {}
      for (final String id
          in followedChannelIds(FollowedLog.instance.book, _favIds)) {
        if (gen != _showGen) return;
        try {
          take(await EpgRepository.instance.programsBetween(id, from, to));
        } catch (_) {}
      }
      if (gen != _showGen || !mounted) return;
      final bool kids = ParentalControls.instance.kidsMode.value;
      final Map<String, Channel> byId = indexChannelsById(_channels);
      final List<GuideSlot> slots = <GuideSlot>[];
      for (final EpgProgram program in found) {
        final Channel? channel = byId[program.channelId];
        if (channel == null) continue;
        if (kids &&
            (hiddenForKids(channel) || roughLooksAdult(program.title))) {
          continue;
        }
        final bool declared = channel.catchupSupported ||
            (channel.catchupSource != null &&
                channel.catchupSource!.isNotEmpty);
        slots.add(GuideSlot(
          channelId: channel.id,
          channelName: channel.cleanName,
          title: program.title,
          startMs: program.startTime,
          stopMs: program.stopTime,
          catchupDeclared: declared,
        ));
      }
      _guide = slots;
      _guideAtMs = now;
      _replanShows();
      if (mounted) setState(() {});
    } catch (_) {
      if (gen != _showGen || !mounted) return;
      _guide = const <GuideSlot>[];
      _replanShows();
      setState(() {});
    }
  }

  void _openShow(ShowCue cue, {bool fromStart = false, bool replay = false}) {
    final Map<String, Channel> byId = indexChannelsById(_channels);
    final String id =
        replay ? (cue.replayChannelId ?? cue.channelId) : cue.channelId;
    final Channel? target = byId[id];
    unawaited(FollowedLog.instance.markSeen(cue.alertKey));
    setState(() => _banner = null);
    if (target == null || !mounted) return;
    String? url;
    if (fromStart) {
      final Channel? origin = byId[cue.channelId];
      if (origin != null) {
        url = CatchupUrlBuilder.build(
          channel: origin,
          program: EpgProgram(
            channelId: cue.channelId,
            startTime: cue.startMs,
            stopTime: cue.stopMs,
            title: cue.title,
          ),
        );
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(
          channels: <Channel>[target],
          startIndex: 0,
          startAtUrl: (url != null && url.isNotEmpty) ? url : null,
        ),
      ),
    );
  }

  void _dismissBanner() {
    final ShowCue? cue = _banner;
    if (cue != null) {
      unawaited(FollowedLog.instance.markSeen(cue.alertKey));
    }
    setState(() => _banner = null);
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

  /// Aucune playlist enregistrée sur la box → le QR téléphone
  /// a sa place. Une erreur de lecture ne l'affiche pas : on
  /// préfère se taire plutôt que de le montrer à quelqu'un
  /// qui a déjà sa source.
  Future<void> _lookForLocalSource() async {
    try {
      final List<Playlist> lists =
          await PlaylistRepository.instance.getAllPlaylists();
      if (!mounted) return;
      final bool has = lists.isNotEmpty ||
          PlaylistRepository.instance.currentChannels.isNotEmpty;
      setState(() => _hasLocalSource = has);
    } catch (_) {
      if (kDebugMode) debugPrint('[TvHub] lecture des sources impossible');
    }
  }

  Future<void> _initConnectivity() async {
    try {
      _conn = await Connectivity().checkConnectivity();
      // Écran déjà parti pendant l'attente : ne pas s'abonner (fuite).
      if (!mounted) return;
      setState(() {});
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
    _shelfDebounce?.cancel();
    _popularDebounce?.cancel();
    _favSub?.cancel();
    _trendSub?.cancel();
    _recentSub?.cancel();
    _popularGen++; // une réponse tardive ne touche plus cet écran
    _showGen++;
    TrendingRepository.instance.stop();
    WatchProgressRepository.instance.removeListener(_scheduleShelves);
    ProgramReminderRepository.instance.removeListener(_scheduleShelves);
    ParentalControls.instance.kidsMode.removeListener(_scheduleShelves);
    TimePickLog.instance.listenable.removeListener(_onTimePicks);
    timePicksFlag.changes.removeListener(_onTimeFlag);
    FollowedLog.instance.listenable.removeListener(_onFollowed);
    followedFlag.changes.removeListener(_onFollowedFlag);
    _featuredGen++;
    _promoGen++;
    _panelDebounce?.cancel();
    AnnouncementRepository.latest.removeListener(_onNotice);
    FeaturedRepository.instance.removeListener(_onFeatured);
    PromoBannerRepository.instance.removeListener(_replanPanel);
    ParentalControls.instance.kidsMode.removeListener(_replanPanel);
    panelNoticeFlag.changes.removeListener(_onPanelFlags);
    featuredFlag.changes.removeListener(_onPanelFlags);
    promoBannerFlag.changes.removeListener(_onPanelFlags);
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
    final String lang = Localizations.localeOf(context).languageCode;
    final Widget? header = _panelHeader(lang);
    final bool hasPersonal = _shelves.hasAny ||
        _timePicks.isNotEmpty ||
        _showCards.isNotEmpty ||
        header != null;

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
                        _HubSearchButton(
                          label: context.l10n.tvNavSearch,
                          onSelect: () => VoiceNavigation.openSearch(),
                        ),
                        const SizedBox(width: 16),
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
                    if (!hasPersonal) ...<Widget>[
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
                      child: hasPersonal
                          ? Column(
                              children: <Widget>[
                                Expanded(
                                  child: TvHomeRails(
                                    model: _shelves,
                                    nowMs: _now.millisecondsSinceEpoch,
                                    initialShelf: _pendingShelfFocus
                                        ? _initialShelf
                                        : null,
                                    timePicks: _timePicks,
                                    timePicksLabel: boxText(
                                      context,
                                      'À cette heure',
                                      'At this hour',
                                    ),
                                    shows: _showCards,
                                    showsLabel: followedWord(lang, 'row'),
                                    onPlayShow: _openShow,
                                    header: header,
                                    onPlayChannel: _playShelf,
                                    onPlayContinue: _playContinue,
                                    onPlayReminder: _playReminder,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _tileRow(context, compact: true),
                              ],
                            )
                          // Aucune playlist sur la box : tuiles un peu plus petites,
                          // et à droite le QR que le téléphone photographie
                          // pour ouvrir « Mon espace » (lien M3U ou Xtream).
                          : _hasLocalSource == false
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Expanded(
                                      child: Center(
                                        child: _tileRow(
                                          context,
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    TvPhoneSourceQr(mac: _mac),
                                  ],
                                )
                              : Center(
                                  child: _tileRow(context, compact: false),
                                ),
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
                            style: TvTokens.mono(16,
                                color: TvTokens.accentBright)),
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

/// Bouton « Recherche » de la barre du haut. Le focus initial reste
/// sur Direct. Le micro de la télécommande ouvre aussi cet écran.
class _HubSearchButton extends StatelessWidget {
  const _HubSearchButton({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
              color: focused ? TvTokens.accent : TvTokens.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.mic_none_rounded,
                  size: 22,
                  color: focused ? TvTokens.onAccent : TvTokens.accent),
              const SizedBox(width: 8),
              Text(label,
                  style: TvTokens.ui(TvDimens.label,
                      weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
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
            color: focused
                ? TvTokens.accent
                : TvTokens.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border:
                Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(ProfileLooks.icon(profile),
                  size: 22,
                  color: focused
                      ? TvTokens.onAccent
                      : ProfileLooks.color(profile)),
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
