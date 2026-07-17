// =========================================================
//  tv_live_screen.dart — Écran DIRECT (Live TV) 10-foot
// =========================================================
//  Gauche : catégories focusables (le focus met à jour la grille, façon
//  TiviMate). Droite : grille de chaînes virtualisée (logo + nom + n°),
//  focusable. OK sur une chaîne → lecteur plein écran.
//
//  Source = celle poussée par TON panel (PlaylistRepository, alimenté par
//  RemoteSourceRepository). États vides PROFESSIONNELS (pas d'écran mort).
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/crash/crash_reporting.dart';
import '../../../core/curation/title_curator.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../security/data/parental_controls.dart';
import '../../subscription/data/subscription_state.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';
import 'tv_shell.dart';

// Polissage TV-ONLY des libellés (n'altère PAS le curateur partagé/mobile ni le
// nom brut servant au matching flux/EPG) :
//  • « Prime: 13e Rue » → « Prime · 13e Rue » (deux-points en séparateur élégant,
//    SAUF entre chiffres pour ne pas casser une heure « 20:30 ») ;
//  • on retire un séparateur orphelin en début/fin et les espaces multiples.
final RegExp _tvColonSep = RegExp(r'(?<!\d):(?!\d)');
final RegExp _tvMultiSpace = RegExp(r'\s{2,}');
final RegExp _tvOrphanSep = RegExp(r'^[\s·:|\-–—]+|[\s·:|\-–—]+$');
String _tvPretty(String s) {
  String r = s.replaceAll(_tvColonSep, ' · ');
  r = r.replaceAll(_tvMultiSpace, ' ');
  r = r.replaceAll(_tvOrphanSep, '');
  return r.trim();
}

// Filet TV pour les LIBELLÉS DE CATÉGORIE : retire les mots techniques résiduels
// (RAW, HEVC, VIP, FHD, 4K, HD…) que le curateur partagé aurait laissés. On ne
// l'applique QU'AUX catégories (les noms de chaînes ont déjà leur qualité
// extraite en chip). Mots ENTIERS uniquement (jamais au milieu d'un mot).
final RegExp _tvCodecWords = RegExp(
    r'(^|\s)(raw|hevc|h\.?264|h\.?265|vip|fhd|uhd|sd|4k|hd|60\s?fps|50\s?fps|multi|multilang|backup|bkp)(?=\s|$)',
    caseSensitive: false);
String _tvStripCodec(String s) {
  String r = s;
  String before;
  int safety = 3; // occurrences adjacentes : quelques passes suffisent
  do {
    before = r;
    r = r.replaceAll(_tvCodecWords, ' ');
    safety--;
  } while (before != r && safety > 0);
  return r;
}

class TvLiveScreen extends StatefulWidget {
  const TvLiveScreen({super.key});

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  // FLUX = SIGNAL, plus SOURCE. On n'absorbe PLUS toute la liste de chaînes en
  // RAM (cause racine des crashs mémoire « façon TiviMate » sur grosses
  // sources). Le flux sert seulement de DÉCLENCHEUR : quand la source vient
  // d'être (re)synchronisée, on recharge le CATALOGUE (catégories + compteurs)
  // depuis SQLite via un AGRÉGAT léger, et la grille lit la base par PAGES.
  StreamSubscription<List<Channel>>? _sub;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<String>>? _recentSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  List<String> _recentIds = RecentlyWatchedRepository.instance.current;

  // --- CATALOGUE (catégories + compteurs), chargé par AGRÉGAT SQL ---
  // ZÉRO chaîne matérialisée ici : juste (nom de catégorie, nombre). Tient
  // 100 000 chaînes sans pression mémoire.
  List<({String category, int count})> _catCounts =
      const <({String category, int count})>[];
  int _totalCount = 0; // total chaînes LIVE (pseudo-catégorie « Toutes »)
  Map<String, int> _realCatCounts = const <String, int>{};
  List<String> _dispCats = const <String>[]; // clés affichées (pseudo + réelles)
  String? _selectedCat;
  bool _ready = false; // a-t-on chargé le catalogue au moins une fois ?

  // --- GRILLE PAGINÉE de la catégorie sélectionnée ---
  // Seules les pages déjà défilées vivent en RAM (quelques centaines de
  // chaînes), JAMAIS toute la catégorie. C'est LE principe anti-OOM « TiviMate ».
  List<Channel> _shownList = const <Channel>[];
  int _pageCursor = 0; // dernier local_id chargé (pagination keyset)
  bool _hasMore = true; // reste-t-il des pages à charger ?
  bool _loadingPage = false; // garde-fou anti-réentrance d'un chargement
  // « Époque » de la grille : incrémentée à chaque changement de catégorie. Un
  // chargement de page parti pour l'ancienne catégorie est ignoré à son retour
  // si l'époque a changé (jamais de mélange de deux catégories dans la grille).
  int _gridEpoch = 0;

  // --- RANGÉES DÉRIVÉES BORNÉES (résolues par external_id, pas de scan) ---
  List<Channel> _favCh = const <Channel>[];
  List<Channel> _recentCh = const <Channel>[];
  // « Pour vous » : reco BORNÉE (top catégories préférées -> 1re page SQL de
  // chacune, hors déjà-vues). Jamais de scan complet -> anti-OOM.
  List<Channel> _forYouCh = const <Channel>[];

  /// Pseudo-catégories (sentinelles internes, pas de vraies catégories de la
  /// source). Résolues par ID (listes BORNÉES) → aucun scan complet de la base.
  static const String _kRecentCat = 'k.recent';
  static const String _kForYouCat = 'k.foryou';
  static const String _kFavCat = '★ favoris'; // ★ favoris (clé interne)
  static const String _kAllCat = 'k.all'; // « Toutes » (toutes catégories)

  // Re-synchro de la source poussée par le panel. CRUCIAL : sans ça, l'app ne
  // récupérait la source qu'au tout 1er démarrage ; si le revendeur activait
  // APRÈS, la TV restait « Aucune chaîne » jusqu'au redémarrage. Ici on re-tente
  // tant qu'on n'a aucune chaîne.
  Timer? _syncTimer;
  // Anti-jank D-pad : le focus d'une catégorie change la grille (et lance une
  // requête SQL de 1re page). En défilement rapide à la télécommande, on
  // DÉBOUNCE pour ne charger que la catégorie où le focus se POSE.
  Timer? _catDebounce;
  // Coalescence des rechargements déclenchés par les flux (catalogue / rangées).
  Timer? _catalogDebounce;
  Timer? _railsDebounce;
  // HERO « aperçu live » : chaîne survolée dans la grille. DÉBOUNCÉ.
  Channel? _previewCh;
  Timer? _previewDebounce;
  // Chaîne à re-focuser au RETOUR du lecteur (désignée par _openPlayer). La
  // carte correspondante reprend le focus à son prochain build (déterministe).
  String? _restoreFocusId;
  // Source du lancement : true = rangée « Reprendre », false = grille. Évite
  // qu'une chaîne présente DANS LES DEUX vole le focus du mauvais côté au retour.
  bool _restoreFromRail = false;
  bool _syncing = false;
  RemoteSyncResult? _lastSync;
  // Garde-fou : on borne le nombre de ré-imports AUTOMATIQUES de la source.
  // Sans ça, si la source ne charge jamais (échec/box surchargée), le timer 12 s
  // relancerait un fetch+parse complet INDÉFINIMENT. Au-delà, seul le bouton
  // manuel ré-essaie.
  int _autoSyncAttempts = 0;
  static const int _kMaxAutoSync = 6;
  // Taille d'une page de grille. ~150 chaînes : un écran TV en montre ~20 ; on
  // garde quelques pages d'avance pour un scroll fluide, RAM bornée.
  static const int _kPageSize = 150;

  // ÉTAPE 1 — source-push « à chaud ». Même une fois des chaînes chargées, on
  // re-vérifie le panel à intervalle LENT (~5 min) : si le revendeur pousse /
  // échange la source à distance, la box la récupère SANS redémarrage. Compteur
  // de ticks du timer 12 s (25 × 12 s ≈ 5 min).
  int _slowSyncTicks = 0;
  static const int _kSlowSyncEvery = 25;
  String _mac = '…'; // adresse de CET appareil (à montrer si pas de chaînes)
  // Clé STABLE de la grille : quand le bandeau « Reprendre » apparaît/disparaît,
  // la mise en page change ; cette GlobalKey PRÉSERVE le scroll et le focus.
  final GlobalKey _liveGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Favoris en direct : la pseudo-catégorie « ★ Favoris » se met à jour seule.
    FavoritesRepository.instance.initialize();
    _favSub =
        FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      _favIds = ids;
      _scheduleRailsRefresh();
    });
    // Historique « Récemment » en direct.
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((List<String> ids) {
      _recentIds = ids;
      _scheduleRailsRefresh();
    });
    // Le flux de chaînes ne sert PLUS que de SIGNAL « la source a changé » : on
    // recharge alors le catalogue (agrégat SQL) — on n'absorbe plus la liste.
    _sub = PlaylistRepository.instance.channelsStream
        .listen((_) => _scheduleCatalogRefresh());
    // Code affiché sur l'état vide — NU (sans « MK: ») : le panel du
    // revendeur préfixe déjà « MK », on évite le doublon au collage.
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
    // MODE SANS ÉCHEC : on NE relance PAS le ré-import automatique (étape
    // gourmande qu'on veut éviter pour casser la boucle). Bouton manuel restant.
    if (!BootGuard.instance.safeMode) {
      _kickSourceSync();
      _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_totalCount == 0 && _autoSyncAttempts < _kMaxAutoSync) {
          _autoSyncAttempts++;
          _kickSourceSync();
        } else if (_totalCount > 0) {
          _autoSyncAttempts = 0; // la source a fini par charger → on réarme
          // Re-vérif LENTE du panel (Étape 1, source-push à chaud). Sûr :
          // sync() est idempotent (dédup) → simple GET tant qu'il n'y a rien
          // de neuf ; ré-import seulement si la source a réellement changé.
          // Invisible : _syncing ne pilote que l'état « écran vide ».
          _slowSyncTicks++;
          if (_slowSyncTicks >= _kSlowSyncEvery) {
            _slowSyncTicks = 0;
            _kickSourceSync();
          }
        }
      });
    }
    // Mode Enfants : si le parent l'active/désactive, on recharge (re-filtrage).
    ParentalControls.instance.kidsMode.addListener(_onKidsModeChanged);
    // Chargement initial : rangées + catalogue + 1re page.
    _refreshAll();
  }

  /// Le Mode Enfants a basculé → on recharge rangées + catalogue + page courante
  /// (le filtre Adulte s'applique à chaque page chargée).
  void _onKidsModeChanged() {
    if (mounted) _refreshAll();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _favSub?.cancel();
    _recentSub?.cancel();
    _syncTimer?.cancel();
    _catDebounce?.cancel();
    _catalogDebounce?.cancel();
    _railsDebounce?.cancel();
    _previewDebounce?.cancel();
    _ambient.dispose();
    ParentalControls.instance.kidsMode.removeListener(_onKidsModeChanged);
    super.dispose();
  }

  // ============================================================
  //  CHARGEMENT DES DONNÉES (SQLite — JAMAIS toute la liste en RAM)
  // ============================================================

  /// Recharge TOUT : rangées dérivées (favoris/récents) puis catalogue + page.
  Future<void> _refreshAll() async {
    await _resolveDerivedRails();
    await _computeForYou();
    await _loadCatalog();
  }

  /// Calcule « Pour vous » de façon BORNÉE (anti-OOM) : on déduit les catégories
  /// préférées de l'historique (poids 2) et des favoris (poids 1), puis on
  /// charge la 1re PAGE SQL de chacune des meilleures catégories (jamais toute
  /// la base), en excluant ce qui est déjà vu/favori. Cap à 60 chaînes.
  Future<void> _computeForYou() async {
    final Map<String, double> catScore = <String, double>{};
    void tally(List<Channel> src, double w) {
      for (final Channel c in src) {
        final String cat =
            c.category.trim().isEmpty ? 'Autres' : c.category.trim();
        catScore[cat] = (catScore[cat] ?? 0) + w;
      }
    }

    tally(_recentCh, 2.0); // l'historique pèse le plus
    tally(_favCh, 1.0);
    if (catScore.isEmpty) {
      if (mounted) setState(() => _forYouCh = const <Channel>[]);
      return;
    }
    // Top catégories préférées (au plus 4).
    final List<MapEntry<String, double>> ranked = catScore.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    final List<String> prefCats =
        ranked.take(4).map((MapEntry<String, double> e) => e.key).toList();

    final Set<String> exclude = <String>{..._recentIds, ..._favIds};
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<Channel> out = <Channel>[];
    final Set<String> seen = <String>{};
    for (final String cat in prefCats) {
      final page = await PlaylistRepository.instance
          .getChannelsPage(category: cat, limit: 40);
      for (final Channel c in page.channels) {
        if (exclude.contains(c.id)) continue;
        if (kids && _isAdult(c)) continue;
        if (seen.add(c.id)) out.add(c);
        if (out.length >= 60) break;
      }
      if (out.length >= 60) break;
    }
    if (!mounted) return;
    setState(() => _forYouCh = out);
  }

  void _scheduleCatalogRefresh() {
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refreshAll();
    });
  }

  void _scheduleRailsRefresh() {
    _railsDebounce?.cancel();
    _railsDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _onRailsChanged();
    });
  }

  /// Résout les rangées BORNÉES (favoris/récemment) par external_id : on ne
  /// charge que les quelques dizaines de chaînes concernées (aucun scan).
  Future<void> _resolveDerivedRails() async {
    final bool kids = ParentalControls.instance.kidsMode.value;
    final PlaylistRepository repo = PlaylistRepository.instance;

    List<Channel> fav = const <Channel>[];
    if (_favIds.isNotEmpty) {
      fav = await repo.getChannelsByExternalIds(_favIds.toList(growable: false));
      if (kids) {
        fav = fav.where((Channel c) => !_isAdult(c)).toList(growable: false);
      }
    }

    List<Channel> recent = const <Channel>[];
    if (_recentIds.isNotEmpty) {
      final List<Channel> fetched =
          await repo.getChannelsByExternalIds(_recentIds);
      final Map<String, Channel> byId = <String, Channel>{
        for (final Channel c in fetched) c.id: c,
      };
      // Ordre HISTORIQUE (le plus récent d'abord), pas l'ordre playlist.
      recent = <Channel>[
        for (final String id in _recentIds)
          if (byId[id] != null && !(kids && _isAdult(byId[id]!))) byId[id]!,
      ];
    }

    if (!mounted) return;
    setState(() {
      _favCh = fav;
      _recentCh = recent;
    });
  }

  /// Les rangées favoris/récents ont changé : on re-résout puis on met à jour la
  /// liste affichée SI on est sur une pseudo-catégorie (sans toucher la grille
  /// d'une vraie catégorie → pas de saut de défilement intempestif).
  Future<void> _onRailsChanged() async {
    await _resolveDerivedRails();
    await _computeForYou();
    if (!mounted) return;
    setState(() {
      _rebuildDispCats();
      if (_selectedCat == _kFavCat) {
        _shownList = _favCh;
      } else if (_selectedCat == _kRecentCat) {
        _shownList = _recentCh;
      } else if (_selectedCat == _kForYouCat) {
        _shownList = _forYouCh;
      }
    });
    // Si la pseudo-catégorie affichée s'est VIDÉE, on retombe sur « Toutes ».
    if ((_selectedCat == _kFavCat && _favCh.isEmpty) ||
        (_selectedCat == _kRecentCat && _recentCh.isEmpty) ||
        (_selectedCat == _kForYouCat && _forYouCh.isEmpty)) {
      _applySelection(_kAllCat, force: true);
    }
  }

  /// (Re)construit la liste des catégories affichées à partir des rangées et du
  /// catalogue courants : pseudo en tête, puis « Toutes », puis les réelles.
  void _rebuildDispCats() {
    final List<String> cats = <String>[];
    if (_forYouCh.isNotEmpty) cats.add(_kForYouCat);
    if (_favCh.isNotEmpty) cats.add(_kFavCat);
    if (_recentCh.isNotEmpty) cats.add(_kRecentCat);
    if (_catCounts.isNotEmpty) cats.add(_kAllCat);
    cats.addAll(_catCounts.map((e) => e.category));
    _dispCats = cats;
  }

  /// Charge le CATALOGUE (catégories + compteurs) par AGRÉGAT SQL, puis choisit
  /// la catégorie courante et charge sa 1re page si besoin. ZÉRO chaîne en RAM
  /// pour cette étape (juste des compteurs).
  Future<void> _loadCatalog() async {
    final PlaylistRepository repo = PlaylistRepository.instance;
    final List<({String category, int count})> counts =
        await repo.getActiveCategoryCounts();
    if (!mounted) return;

    int total = 0;
    final Map<String, int> real = <String, int>{};
    for (final e in counts) {
      total += e.count;
      real[e.category] = e.count;
    }

    // La sélection courante est-elle toujours valide ?
    final String? sel = _selectedCat;
    final bool selValid = sel != null &&
        (sel == _kAllCat ||
            (sel == _kFavCat && _favCh.isNotEmpty) ||
            (sel == _kRecentCat && _recentCh.isNotEmpty) ||
            (sel == _kForYouCat && _forYouCh.isNotEmpty) ||
            real.containsKey(sel));

    CrashReporting.instance
        .recordMemoryBreadcrumbWithCounts('tvlive.catalog', channels: total);

    setState(() {
      _catCounts = counts;
      _totalCount = total;
      _realCatCounts = real;
      _ready = true;
      _rebuildDispCats();
    });

    if (!selValid) {
      // Défaut : 1re VRAIE catégorie (comportement historique), sinon « Toutes ».
      final String? next = counts.isNotEmpty
          ? counts.first.category
          : (_dispCats.isNotEmpty ? _dispCats.first : null);
      if (next != null) _applySelection(next, force: true);
    } else if (_shownList.isEmpty &&
        sel != _kFavCat &&
        sel != _kRecentCat &&
        sel != _kForYouCat) {
      // Sélection valide mais grille vide (1er chargement) → charger la page.
      _applySelection(sel!, force: true);
    } else if (sel == _kForYouCat) {
      // « Pour vous » vient peut-être d'être recalculé → on rafraîchit la grille.
      setState(() => _shownList = _forYouCh);
    }
  }

  // ============================================================
  //  PAGINATION DE LA GRILLE
  // ============================================================

  /// Sélectionne une catégorie : réinitialise la pagination puis charge la 1re
  /// page (catégorie réelle / « Toutes ») ou affiche la liste BORNÉE (pseudo).
  void _applySelection(String cat, {bool force = false}) {
    if (!force && _selectedCat == cat) return;
    _gridEpoch++; // invalide tout chargement de page en vol
    _catDebounce?.cancel();
    setState(() {
      _selectedCat = cat;
      _pageCursor = 0;
      _hasMore = true;
      _loadingPage = false;
      if (cat == _kFavCat) {
        _shownList = _favCh;
        _hasMore = false;
      } else if (cat == _kRecentCat) {
        _shownList = _recentCh;
        _hasMore = false;
      } else if (cat == _kForYouCat) {
        _shownList = _forYouCh;
        _hasMore = false;
      } else {
        _shownList = const <Channel>[];
      }
    });
    if (cat != _kFavCat && cat != _kRecentCat && cat != _kForYouCat) {
      _loadPage(); // catégorie réelle ou « Toutes »
    }
  }

  /// Charge la PROCHAINE page de la catégorie courante depuis SQLite (keyset).
  /// Garde-fous : pas de réentrance, pas de chargement s'il n'y a plus de pages,
  /// et on IGNORE le résultat si l'utilisateur a changé de catégorie entre-temps.
  Future<void> _loadPage() async {
    if (_loadingPage || !_hasMore) return;
    final String? cat = _selectedCat;
    // Pseudo-catégories = listes déjà en mémoire (pas de pagination SQL).
    if (cat == _kFavCat || cat == _kRecentCat || cat == _kForYouCat) return;
    _loadingPage = true;
    final int epoch = _gridEpoch;
    final String? catArg = (cat == null || cat == _kAllCat) ? null : cat;
    try {
      final res = await PlaylistRepository.instance.getChannelsPage(
        category: catArg,
        afterLocalId: _pageCursor,
        limit: _kPageSize,
      );
      if (!mounted || epoch != _gridEpoch) return; // catégorie changée
      final bool kids = ParentalControls.instance.kidsMode.value;
      final List<Channel> page = kids
          ? res.channels
              .where((Channel c) => !_isAdult(c))
              .toList(growable: false)
          : res.channels;
      setState(() {
        _shownList = <Channel>[..._shownList, ...page];
        _pageCursor = res.nextCursor;
        _hasMore = res.hasMore;
      });
    } finally {
      // Ne ré-arme le drapeau que si l'époque n'a pas changé (sinon
      // _applySelection l'a déjà remis à false pour la nouvelle catégorie).
      if (epoch == _gridEpoch) _loadingPage = false;
    }
  }

  Future<void> _kickSourceSync() async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    final RemoteSyncResult r = await RemoteSourceRepository.sync();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSync = r;
    });
  }

  /// Vrai si la chaîne est classée « Adulte » (Mode Enfants). O(1) : on lit le
  /// genre DÉJÀ classé et mis en cache du modèle Channel (jamais de re-classif).
  static bool _isAdult(Channel c) => c.genre == ChannelGenre.adult;

  // ============================================================
  //  NAVIGATION LECTEUR
  // ============================================================

  /// Ouvre le lecteur pour [index] de [list], PUIS — au retour — DÉSIGNE la
  /// chaîne quittée pour que SA carte reprenne le focus (on revient où on était).
  Future<void> _openPlayerWith(List<Channel> list, int index,
      {required bool fromRail}) async {
    if (index < 0 || index >= list.length) return;
    final String chId = list[index].id;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
    if (!mounted) return;
    setState(() {
      _restoreFocusId = chId;
      _restoreFromRail = fromRail;
    });
  }

  Future<void> _openPlayer(int index) =>
      _openPlayerWith(_shownList, index, fromRail: false);

  void _setPreview(Channel c) {
    // Focuser une CHAÎNE annule tout changement de CATÉGORIE en attente.
    _catDebounce?.cancel();
    if (_previewCh?.id == c.id) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _previewCh?.id != c.id) {
        // PAS de setState ici : seule l'ambiance (ValueNotifier ciblé)
        // dépend de la chaîne survolée — un setState racine reconstruisait
        // C-Liste + rangée « Reprendre » + ~30 cartes à CHAQUE cran de D-pad.
        _previewCh = c;
        _updateAmbient(c); // gradient ambiant dérivé du logo (§6)
      }
    });
  }

  // ============================================================
  //  GRADIENT AMBIANT (§5.3 / §6) — couleur dominante du logo, EN CACHE
  // ============================================================
  //  Le fond de l'écran prend une teinte SOMBRE dérivée de la couleur dominante
  //  du logo de la chaîne survolée. Conforme RÈGLE 4 (perf) : extraction faite
  //  UNE seule fois par chaîne (cache statique), sur une image RÉDUITE (48 px),
  //  et UNIQUEMENT pour le hero (1 image à la fois, après débounce du focus) —
  //  jamais par carte ni dans une liste. Repli : preset de catégorie, sinon or.
  // ValueNotifier (patron tv_channels_screen) : SEUL le fond ambiant écoute —
  // un changement de teinte ne reconstruit plus l'écran entier.
  final ValueNotifier<Color> _ambient = ValueNotifier<Color>(TvTokens.bg);
  static final Map<String, Color> _domCache = <String, Color>{};

  Color _categoryAmbient(String category) {
    final String c = category.toLowerCase();
    if (c.contains('sport')) return const Color(0xFF14322A);
    if (c.contains('cin') || c.contains('film') || c.contains('movie')) {
      return const Color(0xFF2A1622);
    }
    if (c.contains('info') || c.contains('news') || c.contains('actu')) {
      return const Color(0xFF1A2436);
    }
    if (c.contains('music') || c.contains('musi')) return const Color(0xFF2A1430);
    if (c.contains('kid') || c.contains('enfant')) return const Color(0xFF2E2410);
    if (c.contains('doc') || c.contains('natur')) return const Color(0xFF13281C);
    return const Color(0xFF1C160E); // défaut : or très sombre
  }

  Future<void> _updateAmbient(Channel c) async {
    final Color? cached = _domCache[c.id];
    if (cached != null) {
      if (mounted) _ambient.value = cached;
      return;
    }
    // Repli immédiat (preset de catégorie) pendant l'extraction.
    Color color = _categoryAmbient(c.category);
    if (mounted) _ambient.value = color;
    final String? url = c.logoUrl;
    if (url == null || url.isEmpty) {
      _domCache[c.id] = color;
      return;
    }
    try {
      // ResizeImage : le paramètre `size` de PaletteGenerator ne borne PAS
      // le décodage — le logo partait en pleine résolution (~4 Mo/logo)
      // dans l'ImageCache pour extraire UNE couleur (churn d'évictions des
      // vignettes visibles). Même motif que tv_poster_prefetch.
      final PaletteGenerator pal = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          CachedNetworkImageProvider(url),
          width: 64,
          policy: ResizeImagePolicy.fit,
        ),
        size: const Size(48, 48),
        maximumColorCount: 8,
      );
      final Color? dom = pal.vibrantColor?.color ??
          pal.dominantColor?.color ??
          pal.mutedColor?.color;
      if (dom != null) {
        // On ASSOMBRIT vers un fond matte (jamais une couleur vive plein écran).
        color = Color.lerp(TvTokens.bg, dom, 0.35)!;
      }
    } catch (_) {
      // extraction impossible → on garde le preset de catégorie.
    }
    // Garde-fou mémoire (même patron que _nameMemo) : une Color par chaîne
    // survolée, sans purge → croissance continue en endurance sur les très
    // gros bouquets.
    if (_domCache.length > 2000) _domCache.clear();
    _domCache[c.id] = color;
    if (mounted && _previewCh?.id == c.id) _ambient.value = color;
  }

  // ============================================================
  //  C-LISTE (catégories)
  // ============================================================

  /// Compteur affiché dans la C-Liste pour une catégorie (vraie ou pseudo).
  int _countOf(String cat) {
    if (cat == _kFavCat) return _favCh.length;
    if (cat == _kRecentCat) return _recentCh.length;
    if (cat == _kForYouCat) return _forYouCh.length;
    if (cat == _kAllCat) return _totalCount;
    return _realCatCounts[cat] ?? 0;
  }

  /// Sélection immédiate (OK sur une catégorie).
  void _select(String cat) => _applySelection(cat);

  /// Sélection DÉBOUNCÉE (focus D-pad) : on attend que le focus se pose ~220 ms
  /// avant de charger la nouvelle catégorie → plus de requête à chaque case
  /// traversée à la télécommande.
  void _selectDebounced(String cat) {
    if (_selectedCat == cat) return;
    _catDebounce?.cancel();
    _catDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _applySelection(cat);
    });
  }

  /// Libellé visible d'une catégorie (les sentinelles sont traduites/ornées).
  String _catLabel(BuildContext context, String cat) {
    if (cat == _kFavCat) return '★ ${context.l10n.navFavorites}';
    if (cat == _kRecentCat) return context.l10n.tvRecently;
    if (cat == _kForYouCat) return context.l10n.tvLiveForYou;
    if (cat == _kAllCat) return '📺 ${context.l10n.filterAll}';
    // Catégorie réelle : on NETTOIE le libellé affiché (FR|/UK|, RAW, 60fps,
    // hevc…) via le curateur PARTAGÉ (lecture seule) + polissage TV. La clé brute
    // reste INTACTE pour le filtrage SQL.
    final String pretty =
        _tvPretty(_tvStripCodec(TitleCurator.curateCategory(cat)));
    return pretty.isEmpty ? cat : pretty;
  }

  @override
  Widget build(BuildContext context) {
    // ENVELOPPE MATERIAL — CORRIGE LES « LIGNES JAUNES » (photo client) :
    // cet écran est poussé sans Scaffold ; sans ancêtre Material, chaque
    // Text hérite du style d'erreur Flutter (soulignement jaune). L'enveloppe
    // est transparente : zéro changement visuel autre que la disparition
    // des soulignements.
    return Material(type: MaterialType.transparency, child: _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    if (_totalCount == 0) {
      // États PRÉCIS au lieu d'un « écran mort » :
      //  • pas encore prêt / en cours / réseau → « Recherche de tes chaînes… »
      //  • source refusée → identifiants invalides côté panel
      //  • rien d'assigné → message d'activation habituel
      final bool searching = !_ready ||
          _syncing ||
          _lastSync == null ||
          _lastSync == RemoteSyncResult.networkError;
      final String title;
      final String subtitle;
      if (searching) {
        title = context.l10n.tvSearchingChannels;
        subtitle = context.l10n.tvNoChannelsHelp;
      } else if (_lastSync == RemoteSyncResult.sourceFailed) {
        title = context.l10n.tvNoChannels;
        subtitle = context.l10n.tvSourceInvalid;
      } else {
        title = context.l10n.tvNoChannels;
        subtitle = context.l10n.tvNoChannelsHelp;
      }
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // ===== Gauche : message + MAC + actions =====
            SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(searching ? Icons.wifi_find_rounded : Icons.live_tv_rounded,
                      size: 52, color: TvTokens.mutedDim),
                  const SizedBox(height: 14),
                  Text(title, style: TvTokens.display(30, color: TvTokens.text)),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: TvTokens.ui(15, color: TvTokens.mutedDim)),
                  const SizedBox(height: 18),
                  // ----- Adresse de CET appareil (MAC) -----
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: TvTokens.card,
                      borderRadius: BorderRadius.circular(TvTokens.rCard),
                      border: Border.all(color: TvTokens.lineSoft),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(context.l10n.tvDeviceAddress.toUpperCase(),
                            style: TvTokens.ui(12,
                                weight: FontWeight.w600,
                                color: TvTokens.mutedDim,
                                spacing: 2)),
                        const SizedBox(height: 8),
                        Text(_mac,
                            style: TvTokens.mono(28,
                                color: TvTokens.goldBright, spacing: 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ----- Actions : Réessayer + Ajouter sa propre liste -----
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      _ActionPill(
                        icon: Icons.refresh_rounded,
                        label: _syncing
                            ? context.l10n.tvSearchingChannels
                            : context.l10n.tvRetry,
                        autofocus: true,
                        onSelect: _syncing ? null : _kickSourceSync,
                      ),
                      _ActionPill(
                        icon: Icons.playlist_add_rounded,
                        label: context.l10n.tvAddOwnList,
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const TvShell(child: TvAddSourceScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 44),
            // ===== Droite : QR WhatsApp pour contacter le revendeur =====
            TvWhatsAppQr(mac: _mac, size: 190),
          ],
        ),
      );
    }

    // ===== C-LISTE (catégories) — COMPACTE, EN HAUT À DROITE =====
    final Widget cList = _CategoryRail(
      cats: _dispCats,
      selectedCat: _selectedCat,
      // Focus initial sur la GRANDE liste de gauche (accessibilité seniors).
      autofocusFirst: true,
      labelOf: (String c) => _catLabel(context, c),
      countOf: _countOf,
      onSelect: _select,
      onFocusDebounced: _selectDebounced,
    );

    // Grille de chaînes (virtualisée + PAGINÉE depuis SQLite) — toute la zone.
    final Widget grid = _ChannelGrid(
      key: _liveGridKey,
      channels: _shownList,
      onFocused: _setPreview,
      onPlay: _openPlayer,
      // Chargement de la page SUIVANTE quand le focus approche du bas de grille.
      onLoadMore: _loadPage,
      restoreFocusId: _restoreFromRail ? null : _restoreFocusId,
      onRestored: () => _restoreFocusId = null,
    );

    // Rangée « Reprendre » : les ~8 DERNIÈRES chaînes regardées (ordre récent).
    final List<Channel> recentList =
        _recentCh.length > 8 ? _recentCh.sublist(0, 8) : _recentCh;

    return Stack(
      children: <Widget>[
        // ----- FOND AMBIANT (§6) : teinte SOMBRE dérivée de la couleur
        //  dominante du logo survolé. AnimatedContainer = transition douce au
        //  changement de focus (PAS une boucle → conforme RÈGLE 7). Aucun flou.
        // RepaintBoundary : la transition de teinte (450 ms) repeint SA couche,
        // pas celle de la route (C-Liste + grille au-dessus).
        Positioned.fill(
          child: RepaintBoundary(
            child: ValueListenableBuilder<Color>(
              valueListenable: _ambient,
              builder: (BuildContext context, Color ambient, Widget? _) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.5, -0.85),
                      radius: 1.4,
                      colors: <Color>[ambient, TvTokens.bg],
                      stops: const <double>[0.0, 0.72],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // ---- ÉCHANGE DES BLOCS : la LISTE (catégories) en GRANDE colonne
        //  GAUCHE pleine hauteur (lisibilité seniors) ; au centre, « Reprendre »
        //  + la grille. Le menu, lui, est passé en haut à droite (cf. tv_app).
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // GRANDE colonne GAUCHE : la liste, pleine hauteur, gros texte.
            SizedBox(width: 380, child: cList),
            const SizedBox(width: TvDimens.gutter),
            // CENTRE : « Reprendre » en haut + grille en dessous.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ALERTE D'EXPIRATION : bandeau visible quand l'abonnement
                  // expire bientôt (≤ 5 j). Invisible sinon (0 hauteur).
                  const _ExpiryBanner(),
                  _ResumeRail(
                    channels: recentList,
                    onPlay: (int i) =>
                        _openPlayerWith(recentList, i, fromRail: true),
                    restoreFocusId:
                        _restoreFromRail ? _restoreFocusId : null,
                    onRestored: () => _restoreFocusId = null,
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: grid),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// LISTE des catégories — GRANDE colonne de GAUCHE, pleine hauteur (échange de
/// blocs : lisibilité seniors). Remplit la hauteur et défile (lazy, itemExtent).
/// Chaque ligne : libellé (ellipsis) + compteur. Focusable D-pad (or au focus) ;
/// le focus met à jour la grille en DÉBOUNCÉ (pas de recalcul par ligne).
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.cats,
    required this.selectedCat,
    required this.autofocusFirst,
    required this.labelOf,
    required this.countOf,
    required this.onSelect,
    required this.onFocusDebounced,
  });

  final List<String> cats;
  final String? selectedCat;
  final bool autofocusFirst;
  final String Function(String) labelOf;
  final int Function(String) countOf;
  final void Function(String) onSelect;
  final void Function(String) onFocusDebounced;

  // Lignes COMPACTES façon IBO (moins de « zoom »). La liste REMPLIT toute la
  // colonne de gauche et défile (lazy via itemExtent → fluide même sur des
  // milliers de catégories, pas de shrinkWrap).
  static const double _kRowExtent = 50;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) return const SizedBox.shrink();
    // RAIL « VERRE » — PERF BOX TV (§5.2) : on n'utilise PLUS de BackdropFilter
    // (flou temps-réel). Même STATIQUE, un BackdropFilter coûte à CHAQUE image
    // sur le petit GPU d'une box Android TV → micro-saccades diffuses « partout
    // un peu ». On le remplace par un fond dégradé PLUS OPAQUE : visuellement
    // quasi identique (panneau sombre façon verre), mais coût GPU NUL → fluidité
    // constante. (Derrière le rail il n'y a que le fond : le flou ne manque pas.)
    return ClipRRect(
      borderRadius: BorderRadius.circular(TvTokens.rGlass),
      child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                TvTokens.panel.withValues(alpha: 0.92),
                TvTokens.card.withValues(alpha: 0.86),
              ],
            ),
            borderRadius: BorderRadius.circular(TvTokens.rGlass),
            border: Border.all(color: TvTokens.hairline),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Text(
              context.l10n.tvNavLive.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(12,
                  weight: FontWeight.w700,
                  color: TvTokens.mutedDim,
                  spacing: 2),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: _kRowExtent,
              itemCount: cats.length,
              itemBuilder: (BuildContext context, int i) {
                final String cat = cats[i];
                return _CRow(
                  label: labelOf(cat),
                  count: countOf(cat),
                  selected: cat == selectedCat,
                  autofocus: i == 0 && autofocusFirst,
                  onSelect: () => onSelect(cat),
                  onFocused: () {
                    if (selectedCat != cat) onFocusDebounced(cat);
                  },
                );
              },
            ),
          ),
            ],
          ),
        ),
    );
  }
}

/// Une ligne de la C-List : libellé (ellipsis) + compteur aligné à droite.
class _CRow extends StatelessWidget {
  const _CRow({
    required this.label,
    required this.count,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
    required this.onFocused,
  });

  final String label;
  final int count;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        // À la TRANSITION de focus uniquement : l'ancien `if (focused)
        // onFocused()` DANS le builder ré-armait le débounce de catégorie à
        // CHAQUE rebuild de la ligne, pas seulement à l'arrivée du focus.
        onFocusChange: (bool f) {
          if (f) onFocused();
        },
        builder: (BuildContext context, bool focused) {
          // FOCUS UNIQUE : seule la ligne RÉELLEMENT focus porte l'or. La
          // catégorie active-mais-pas-focus = gris discret (jamais d'or).
          final bool active = selected && !focused;
          // Focus/actif = fond PLEIN façon IBO (le « pill »), SANS cadre doré
          // (ce sont les « lignes jaunes » que le client n'aime pas). Texte
          // clair au focus, gris au repos. Aucun or ici.
          final Color bg = focused
              ? TvTokens.sel
              : (active ? TvTokens.sel.withValues(alpha: 0.6) : Colors.transparent);
          final Color fg =
              (focused || active) ? TvTokens.text : TvTokens.muted;
          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Texte COMPACT façon IBO (moins de zoom).
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        fontWeight: (focused || active)
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: fg),
                  ),
                ),
                const SizedBox(width: 10),
                // Compteur ALIGNÉ À DROITE — gris discret (jamais or).
                Text(
                  '$count',
                  style: const TextStyle(
                      fontSize: TvDimens.caption,
                      fontWeight: FontWeight.w700,
                      color: TvTokens.mutedDim),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rangée « Reprendre » (bande haute, à gauche) : les ~8 dernières chaînes
/// regardées, qu'on fait DÉFILER à la télécommande (horizontal). OK = lecture.
/// Masquée s'il n'y a pas encore d'historique.
class _ResumeRail extends StatelessWidget {
  const _ResumeRail({
    required this.channels,
    required this.onPlay,
    this.restoreFocusId,
    this.onRestored,
  });

  final List<Channel> channels;
  final void Function(int index) onPlay;
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  Widget build(BuildContext context) {
    // ÉTAT VIDE (§8) : pas de trou — une invitation discrète.
    if (channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.resumeEyebrow,
                style: TvTokens.ui(13,
                    weight: FontWeight.w800,
                    color: TvTokens.mutedDim,
                    spacing: 2)),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(Icons.history_rounded, size: 18, color: TvTokens.mutedDim),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    context.l10n.tvRecentlyEmpty,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(14, color: TvTokens.mutedDim),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(context.l10n.resumeEyebrow,
              style: TvTokens.ui(13,
                  weight: FontWeight.w800,
                  color: TvTokens.mutedDim,
                  spacing: 2)),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (BuildContext context, int i) => _ResumeCard(
              channel: channels[i],
              onPlay: () => onPlay(i),
              restoreFocusId: restoreFocusId,
              onRestored: onRestored,
            ),
          ),
        ),
      ],
    );
  }
}

/// Une carte de la rangée « Reprendre » : logo + nom (nettoyé), focusable.
class _ResumeCard extends StatefulWidget {
  const _ResumeCard({
    required this.channel,
    required this.onPlay,
    this.restoreFocusId,
    this.onRestored,
  });
  final Channel channel;
  final VoidCallback onPlay;
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  final FocusNode _node = FocusNode();
  // EPG « en ce moment » de la chaîne → barre de progression OR (§5.4). Une
  // seule requête par carte (la rangée « Reprendre » est bornée à ~8).
  late final Future<EpgProgram?> _epg =
      EpgRepository.instance.currentProgram(widget.channel.id);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Channel c = widget.channel;
    // Reprise du focus au retour du lecteur (même mécanisme déterministe que la
    // grille) : si l'écran nous désigne, on (re)prend le focus puis on libère.
    if (widget.restoreFocusId != null && widget.restoreFocusId == c.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.channel.id) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return SizedBox(
      width: 230,
      child: TvFocusable(
        focusNode: _node,
        scale: TvFocusScale.small,
        baseColor: TvTokens.card,
        onSelect: widget.onPlay,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _LogoChip(channel: c, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tvPretty(c.cleanName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Barre de progression OR de l'émission en cours (§5.4). Si pas
              // d'EPG → barre absente (pas de barre grise plate).
              FutureBuilder<EpgProgram?>(
                future: _epg,
                builder: (BuildContext context,
                    AsyncSnapshot<EpgProgram?> snap) {
                  final EpgProgram? p = snap.data;
                  if (p == null) return const SizedBox(height: 3);
                  final int now = DateTime.now().millisecondsSinceEpoch;
                  final int span = p.stopTime - p.startTime;
                  final double prog = span > 0
                      ? ((now - p.startTime) / span).clamp(0.0, 1.0)
                      : 0.0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: prog,
                        backgroundColor: TvTokens.line,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            TvTokens.gold),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelGrid extends StatefulWidget {
  const _ChannelGrid(
      {super.key,
      required this.channels,
      this.onFocused,
      this.onPlay,
      this.onLoadMore,
      this.restoreFocusId,
      this.onRestored});
  final List<Channel> channels;

  /// Signale au parent quelle chaîne vient de prendre le focus (→ hero).
  final void Function(Channel)? onFocused;

  /// Lance le lecteur pour l'index donné (la navigation est gérée par l'écran,
  /// qui sait ensuite RENDRE le focus à la bonne carte au retour).
  final void Function(int index)? onPlay;

  /// Demande au parent de charger la PAGE SUIVANTE (pagination SQLite) quand le
  /// focus/scroll approche du bas de la grille. Le parent ignore l'appel s'il
  /// charge déjà ou s'il n'y a plus de page (garde-fou anti-OOM).
  final VoidCallback? onLoadMore;

  /// Id de la chaîne à re-focuser au retour du lecteur (désigné par l'écran).
  final String? restoreFocusId;

  /// Appelé par la carte une fois le focus repris (l'écran libère le drapeau).
  final VoidCallback? onRestored;

  @override
  State<_ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<_ChannelGrid> {
  // Index de la carte actuellement focus (null = la grille n'a PAS le focus).
  // Sert à ATTÉNUER les voisines (réf. design : c'est ce qui fait « ressortir »
  // la sélection). On passe par un ValueNotifier : au déplacement du focus,
  // SEULES les petites surcouches d'atténuation se reconstruisent, PAS toute la
  // grille → perf préservée sur la box.
  final ValueNotifier<int?> _focused = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoChannelInCategory,
            style: TextStyle(
                fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    // Quand le focus QUITTE la grille (menu / C-List), on retire l'atténuation.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (bool f) {
        if (!f) _focused.value = null;
      },
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        // Mémoire bornée au scroll : on ne garde PAS les cartes hors écran en vie.
        addAutomaticKeepAlives: false,
        // PETITES TUILES CARRÉES (réf. Leanback / Android TV) : logo centré +
        // nom dessous. Plus petites = plus de chaînes à l'écran, look « app
        // icon » mignon. Elles GRANDISSENT au focus (scale + halo, cf.
        // TvFocusable) → l'effet animé reste lisible sans encombrer.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 158,
          mainAxisExtent: 166,
          crossAxisSpacing: TvDimens.gutter,
          mainAxisSpacing: TvDimens.gutter,
        ),
        itemCount: widget.channels.length,
        // Garde-fou index : aucun accès hors borne même si la liste change.
        itemBuilder: (BuildContext context, int i) {
          if (i < 0 || i >= widget.channels.length) {
            return const SizedBox.shrink();
          }
          // PAGINATION : quand on construit une carte proche de la FIN de la
          // page courante, on demande la suivante. Appel sûr pendant build :
          // onLoadMore (côté écran) ne fait que lancer un Future (le setState
          // arrive APRÈS l'await), et il est gardé contre la réentrance.
          if (i >= widget.channels.length - 16) {
            widget.onLoadMore?.call();
          }
          return _ChannelCard(
            channel: widget.channels[i],
            index: i,
            onPlay: widget.onPlay,
            onFocused: widget.onFocused,
            focusedIndex: _focused,
            restoreFocusId: widget.restoreFocusId,
            onRestored: widget.onRestored,
          );
        },
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  const _ChannelCard(
      {required this.channel,
      required this.index,
      this.onPlay,
      this.onFocused,
      this.focusedIndex,
      this.restoreFocusId,
      this.onRestored});
  final Channel channel;
  final int index;
  final void Function(int index)? onPlay;
  final void Function(Channel)? onFocused;

  /// Index focus de la grille → cette carte s'atténue si une AUTRE a le focus.
  final ValueNotifier<int?>? focusedIndex;

  /// Si == id de cette chaîne, la carte reprend le focus (retour lecteur).
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  // FocusNode possédé par la carte (et non par TvFocusable) : on en a besoin
  // pour RE-DEMANDER le focus au retour du lecteur. On le passe à TvFocusable,
  // qui détecte alors qu'il ne lui appartient pas et ne le dispose pas (on s'en
  // charge ici) → pas de double-dispose, pas de fuite. Aucun coût ajouté : sans
  // ça, TvFocusable créait de toute façon son propre node par carte.
  final FocusNode _node = FocusNode();

  // « Pop » de cœur affiché brièvement après un appui long (favori basculé).
  // true = vient d'être ajouté (cœur plein), false = retiré (cœur barré).
  bool _burst = false;
  bool _burstAdded = false;
  Timer? _burstTimer;

  @override
  void dispose() {
    _burstTimer?.cancel();
    _node.dispose();
    super.dispose();
  }

  /// Bascule le favori (appui long sur OK ou au doigt). Affiche un cœur animé
  /// au centre de la carte. L'état persistant (petit cœur en coin) se met à
  /// jour via le flux de favoris de l'écran.
  void _toggleFavorite() {
    final String id = widget.channel.id;
    final bool willBeFav = !FavoritesRepository.instance.isFavorite(id);
    FavoritesRepository.instance.toggle(id);
    HapticFeedback.selectionClick();
    _burstTimer?.cancel();
    setState(() {
      _burst = true;
      _burstAdded = willBeFav;
    });
    _burstTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _burst = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Channel channel = widget.channel;
    final bool fav = FavoritesRepository.instance.current.contains(channel.id);
    final _ParsedName p = _parseName(channel);
    // PREMIUM (§5.5) : zéro jargon codec brut. On garde UN chip qualité
    // (4K/UHD/FHD/HD) + un chip HDR/Dolby s'il existe. Max 2 chips → carte nette.
    final String? quality = p.badges
        .cast<String?>()
        .firstWhere((String? b) => b == '4K' || b == 'FHD' || b == 'HD',
            orElse: () => null);
    final String? premium = p.badges
        .cast<String?>()
        .firstWhere((String? b) => b == 'HDR' || b == 'DOLBY',
            orElse: () => null);
    final List<String> chips = <String>[
      if (quality != null) quality,
      if (premium != null) premium,
    ];
    // RESTAURATION DU FOCUS au retour du lecteur (déterministe) : quand l'écran
    // nous DÉSIGNE (restoreFocusId == notre id), on (re)prend le focus en
    // post-frame puis on libère le drapeau. Déclenché par un rebuild explicite
    // de l'écran au retour → survit aux reconstructions de fond (preview, EPG,
    // récents…) qui faisaient échouer l'ancienne approche.
    if (widget.restoreFocusId != null && widget.restoreFocusId == channel.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.channel.id) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return TvFocusable(
      focusNode: _node,
      scale: TvFocusScale.small,
      // La carte EST la surface (card au repos, sel au focus) → le focus se
      // marque par bordure or + ombre + scale + lueur (cf. tv_focusable). Le
      // contenu est posé PAR-DESSUS via un Stack.
      baseColor: TvTokens.card,
      // Survol → hero du haut + index focus de la grille (atténuation voisines).
      onFocusChange: (bool f) {
        if (f) {
          widget.onFocused?.call(channel);
          widget.focusedIndex?.value = widget.index;
        }
      },
      // Lecture : l'ÉCRAN gère la navigation (et la restauration du focus au
      // retour). La carte se contente de signaler son index.
      onSelect: () => widget.onPlay?.call(widget.index),
      // APPUI LONG sur OK (ou au doigt) → bascule le favori (raccourci rapide).
      onLongPress: _toggleFavorite,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // CONTENU CENTRÉ (petite tuile « app icon ») : logo bien visible au
          // centre + nom dessous, centré. Le monogramme assure qu'il n'y a
          // jamais de carte grise.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Center(child: _LogoChip(channel: channel, size: 80)),
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: TvTokens.text),
                ),
              ],
            ),
          ),
          // Chip qualité (1 seul, discret) en haut-droite — petite tuile = on
          // évite d'encombrer, on garde le plus parlant.
          if (chips.isNotEmpty)
            Positioned(top: 8, right: 8, child: _TagBadge(label: chips.first)),
          // Favori discret en haut-gauche.
          if (fav)
            const Positioned(
              top: 8,
              left: 8,
              child:
                  Icon(Icons.favorite_rounded, size: 15, color: TvTokens.gold),
            ),
          // ATTÉNUATION DES VOISINES : voile sombre quand une AUTRE carte a le
          // focus (peinture simple, pas de saveLayer → peu coûteux ; animé).
          if (widget.focusedIndex != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<int?>(
                  valueListenable: widget.focusedIndex!,
                  builder: (BuildContext context, int? f, Widget? __) {
                    final bool dim = f != null && f != widget.index;
                    return AnimatedContainer(
                      duration: TvDimens.focusAnim,
                      curve: TvDimens.focusCurve,
                      decoration: BoxDecoration(
                        color: dim
                            ? TvTokens.bg.withValues(alpha: 0.45)
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius),
                      ),
                    );
                  },
                ),
              ),
            ),
          // « POP » de cœur au centre après un appui long (favori basculé) :
          // grossit + s'estompe en ~650 ms. Cœur PLEIN or = ajouté, cœur BARRÉ
          // = retiré. Purement visuel (IgnorePointer) → n'intercepte aucun focus.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedScale(
                scale: _burst ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _burst ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Center(
                    child: Icon(
                      _burstAdded
                          ? Icons.favorite_rounded
                          : Icons.heart_broken_rounded,
                      size: 40,
                      color: _burstAdded ? TvTokens.gold : TvTokens.mutedDim,
                      shadows: const <Shadow>[
                        Shadow(color: Color(0xCC000000), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Extrait les tags du nom (qualité + VIP/RAW/60 FPS/HEVC/LIVE) en casse
  /// uniforme et renvoie le nom NETTOYÉ + la liste des badges.
  ///
  /// PERF FLUIDITÉ : regex COMPILÉES UNE FOIS (statique) + résultat MÉMOÏSÉ par
  /// nom. Avant : 8 RegExp recompilées + exécutées à CHAQUE carte entrant à
  /// l'écran → pic CPU à chaque frame de scroll. Maintenant : 0 recompile, 0
  /// recalcul pour un nom déjà vu. (Aucun impact mémoire/démarrage : pas de
  /// pré-chargement, juste du calcul évité.)
  static final List<(String, RegExp)> _badgeRules = <(String, RegExp)>[
    ('4K', RegExp(r'\b(4K|UHD|2160P?)\b', caseSensitive: false)),
    ('FHD', RegExp(r'\b(FHD|1080P?)\b', caseSensitive: false)),
    ('HD', RegExp(r'\bHD\b', caseSensitive: false)),
    // Chips premium (§5.5) : on les EXTRAIT (donc retirés du nom affiché) et on
    // les ré-affiche en badge propre, jamais en jargon brut.
    ('HDR', RegExp(r'\bHDR(10)?\+?\b', caseSensitive: false)),
    ('DOLBY', RegExp(r'\b(DOLBY|ATMOS|DTS|DDP?|EAC3|DV)\b', caseSensitive: false)),
    ('HEVC', RegExp(r'\b(HEVC|H\.?265)\b', caseSensitive: false)),
    ('60 FPS', RegExp(r'\b60\s?FPS\b', caseSensitive: false)),
    ('VIP', RegExp(r'\bVIP\b', caseSensitive: false)),
    ('RAW', RegExp(r'\bRAW\b', caseSensitive: false)),
    ('LIVE', RegExp(r'\bLIVE\b', caseSensitive: false)),
  ];
  static final RegExp _multiSpace = RegExp(r'\s{2,}');
  static final RegExp _leadSep = RegExp(r'^[\s|·\-–]+');
  static final RegExp _trailSep = RegExp(r'[\s|·\-–]+$');
  static final Map<String, _ParsedName> _nameMemo = <String, _ParsedName>{};

  static _ParsedName _parseName(Channel c) {
    final String key = c.cleanName;
    final _ParsedName? hit = _nameMemo[key];
    if (hit != null) return hit;
    String n = key;
    final List<String> badges = <String>[];
    for (final (String label, RegExp re) in _badgeRules) {
      if (re.hasMatch(n)) {
        badges.add(label);
        n = n.replaceAll(re, ' ');
      }
    }
    n = n
        .replaceAll(_multiSpace, ' ')
        .replaceAll(_leadSep, '')
        .replaceAll(_trailSep, '')
        .trim();
    n = _tvPretty(n); // « Prime: 13e Rue » → « Prime · 13e Rue » (TV-only)
    if (n.isEmpty) n = key; // garde-fou : jamais de nom vide
    final _ParsedName result = _ParsedName(n, badges);
    if (_nameMemo.length > 4000) _nameMemo.clear(); // garde-fou mémoire
    _nameMemo[key] = result;
    return result;
  }
}

/// Nom de chaîne nettoyé + ses badges extraits.
class _ParsedName {
  const _ParsedName(this.name, this.badges);
  final String name;
  final List<String> badges;
}

/// Petit badge discret (or sur fond or ~12 %), placé APRÈS le nom.
class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    // Chip qualité premium (§5.5) : bordure hairline OR, texte or, majuscules
    // espacées. Rayon badges = 8 dp.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: TvTokens.badgeBg,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
        border: Border.all(color: TvTokens.hairline),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: TvTokens.gold)),
    );
  }
}

/// Logo PETIT en chip (haut-gauche de la carte) : taille NORMALISÉE pour que
/// tous les logos pèsent visuellement pareil (jamais un logo qui remplit la
/// carte à côté d'un mini-logo). Réutilise [_Logo] (contain + repli initiales).
class _LogoChip extends StatelessWidget {
  const _LogoChip({required this.channel, this.size = 76});
  final Channel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Logo AGRANDI (§5.1) + fallback MONOGRAMME (jamais de carte grise, §6).
    return TvChannelLogo(
      logoUrl: channel.logoUrl,
      label: channel.cleanName,
      size: size,
      radius: 10,
    );
  }
}

/// Petit bouton-pilule focusable (or au focus). Utilisé sur l'accueil vide
/// (« Réessayer », « J'ajoute ma propre liste »).
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 9),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// Bandeau d'ALERTE D'EXPIRATION (auto) : visible sur l'accueil quand
/// l'abonnement (payant ou essai) expire dans ≤ SubscriptionState.kExpiryWarnDays
/// jours. Pousse au renouvellement → moins d'abonnés perdus. Invisible sinon
/// (0 hauteur). Purement informatif (pas focusable). Se met à jour tout seul
/// (ListenableBuilder sur SubscriptionState, alimenté par le heartbeat).
class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionState.instance,
      builder: (BuildContext context, Widget? _) {
        final SubscriptionState sub = SubscriptionState.instance;
        if (!sub.isExpiringSoon) return const SizedBox.shrink();
        final int d = sub.daysUntilExpiry ?? 0;
        final String quand = d <= 0
            ? context.l10n.tvLiveExpiryToday
            : (d == 1
                ? context.l10n.tvLiveExpiryTomorrow
                : context.l10n.tvLiveExpiryInDays(d));
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: TvTokens.badgeBg, // or ~12 %
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.gold),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.hourglass_bottom_rounded,
                  size: 22, color: TvTokens.goldBright),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.tvLiveExpiryBanner(quand),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(15,
                      weight: FontWeight.w600, color: TvTokens.text),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
