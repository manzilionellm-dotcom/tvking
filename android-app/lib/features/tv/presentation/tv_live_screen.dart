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
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/curation/title_curator.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_activity.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/trending_repository.dart';
import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../security/data/parental_controls.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_live_preview.dart';
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
  StreamSubscription<List<Channel>>? _sub;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<String>>? _trendSub;
  StreamSubscription<List<String>>? _recentSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  List<String> _trending = TrendingRepository.instance.current;
  List<String> _recentIds = RecentlyWatchedRepository.instance.current;
  List<Channel> _all = const <Channel>[];
  List<String> _cats = const <String>[];
  String? _selectedCat;
  // Dernière liste BRUTE reçue (avant filtre Mode Enfants) : permet de
  // re-filtrer instantanément quand le parent bascule le Mode Enfants.
  List<Channel> _rawLive = const <Channel>[];

  /// Pseudo-catégories en TÊTE de liste (sentinelles internes, pas de vraies
  /// catégories) : Tendances (les plus regardées EN CE MOMENT) puis Favoris.
  static const String _kTrendCat = 'k.trending';
  static const String _kRecentCat = 'k.recent';
  static const String _kForYouCat = 'k.foryou'; // « Parce que vous avez regardé »
  static const String _kFavCat = '★ favoris'; // ★ favoris (clé interne)

  // Re-synchro de la source poussée par le panel. CRUCIAL : sans ça, l'app
  // ne récupérait la source qu'au tout 1er démarrage ; si le revendeur
  // activait/poussait APRÈS, la TV restait « Aucune chaîne » jusqu'au
  // redémarrage. Ici on re-tente tant qu'on n'a aucune chaîne.
  Timer? _syncTimer;
  // Anti-jank D-pad (P1-5) : le focus d'une catégorie déclenche un _recompute
  // O(n) (reconstruit _byId/byName sur des dizaines de milliers de chaînes). En
  // défilement rapide à la télécommande, on DÉBOUNCE pour ne recalculer que sur
  // la catégorie où le focus se POSE, pas sur chaque case traversée.
  Timer? _catDebounce;
  // Anti-ANR (P0) : les flux favoris/récents/tendances peuvent émettre EN RAFALE
  // (surtout au retour du lecteur : record() → récents, etc.). Sans coalescence,
  // chaque émission relançait un _recompute O(n) → plusieurs recalculs lourds
  // coup sur coup → fil UI saturé → ANR (« app figée » tuée par l'OS). On
  // FUSIONNE : on planifie UN SEUL recompute après une courte pause.
  Timer? _recomputeDebounce;
  // HERO « aperçu live » : chaîne actuellement survolée dans la grille. Le hero
  // en haut la reflète (logo + EN DIRECT + EPG). DÉBOUNCÉ : en défilement rapide
  // on ne met à jour le hero (et sa requête EPG) qu'à l'arrêt du focus.
  // ValueNotifier (et non un champ + setState) : changer la chaîne prévisualisée
  // ne reconstruit QUE la colonne de droite (aperçu + guide), plus TOUT l'écran
  // (catégories + liste + labels regex) à chaque arrêt du focus — c'était une
  // source majeure de saccades en défilement sur les grosses listes.
  final ValueNotifier<Channel?> _previewCh = ValueNotifier<Channel?>(null);
  Timer? _previewDebounce;
  // Chaîne à re-focuser au RETOUR du lecteur (désignée par _openPlayer). La
  // carte correspondante reprend le focus à son prochain build (déterministe).
  String? _restoreFocusId;
  // Source du lancement : true = rangée « Reprendre », false = grille. Évite
  // qu'une chaîne présente DANS LES DEUX vole le focus du mauvais côté au retour.
  bool _restoreFromRail = false;

  /// Vrai pendant que le lecteur plein écran est ouvert : l'aperçu vidéo de la
  /// colonne de droite est alors RETIRÉ de l'arbre (donc fermé) → jamais deux
  /// flux ouverts en même temps.
  bool _playerOpen = false;
  bool _syncing = false;
  RemoteSyncResult? _lastSync;
  // Garde-fou : on borne le nombre de ré-imports AUTOMATIQUES de la source.
  // Sans ça, si la source ne charge jamais (échec/box surchargée), le timer
  // 12 s relancerait un fetch+parse complet INDÉFINIMENT (gaspillage CPU/mémoire,
  // suspect de surchauffe/boucle). Au-delà, seul le bouton manuel ré-essaie.
  int _autoSyncAttempts = 0;
  static const int _kMaxAutoSync = 6;
  // ÉTAPE 1 — source-push « à chaud ». Même une fois des chaînes chargées, on
  // re-vérifie le panel à intervalle LENT (~5 min) : si le revendeur pousse /
  // échange la source à distance, la box la récupère SANS redémarrage. Compteur
  // de ticks du timer 12 s (25 × 12 s ≈ 5 min).
  int _slowSyncTicks = 0;
  static const int _kSlowSyncEvery = 25;
  String _mac = '…'; // adresse de CET appareil (à montrer si pas de chaînes)

  // Pré-calcul en arrière-plan (cf. ChannelPrecompute) : vrai quand TOUTES
  // les chaînes affichées ont leur nom curé + genre + pays en cache. Tant que
  // c'est faux, _recompute SAUTE les parties qui liraient ces valeurs pour
  // toutes les chaînes (Tendances, « Pour vous ») — sinon ~10 M de regex sur
  // le fil UI d'un coup → app figée puis tuée par Android.
  bool _precomputed = false;
  int _ingestGen = 0;

  @override
  void initState() {
    super.initState();
    TvActivity.enter();
    _ingest(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen(_ingest);
    // Favoris en direct : la catégorie « ★ Favoris » se met à jour toute seule.
    FavoritesRepository.instance.initialize();
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      _favIds = ids;
      _scheduleRecompute(); // coalescé (anti-ANR)
    });
    // Tendances en direct : la catégorie « 🔥 Tendances » se met à jour seule.
    TrendingRepository.instance.start();
    _trendSub = TrendingRepository.instance.stream.listen((List<String> names) {
      // Le dépôt ré-émet toutes les 60 s MÊME sans changement : on ignore les
      // émissions identiques → plus de recalcul O(n) + rebuild complet chaque
      // minute pendant que le client navigue.
      if (listEquals(names, _trending)) return;
      _trending = names;
      _scheduleRecompute(); // coalescé (anti-ANR)
    });
    // Historique « 🕒 Récemment » en direct.
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((List<String> ids) {
      _recentIds = ids;
      _scheduleRecompute(); // coalescé (anti-ANR)
    });
    // MAC affichée sur l'état vide : sans elle, impossible de savoir à quel
    // appareil pousser une source dans le panel.
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    // MODE SANS ÉCHEC (boucle de redémarrage détectée) : on NE relance PAS
    // le ré-import automatique de la source — c'est précisément l'étape
    // gourmande qu'on veut éviter pour casser la boucle. Le bouton manuel
    // « Synchroniser » reste disponible.
    if (!BootGuard.instance.safeMode) {
      _kickSourceSync(); // tout de suite à l'ouverture de l'écran
      _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        // Borné : on arrête les tentatives AUTO après _kMaxAutoSync essais.
        if (_all.isEmpty && _autoSyncAttempts < _kMaxAutoSync) {
          _autoSyncAttempts++;
          _kickSourceSync();
        } else if (_all.isNotEmpty) {
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
    // Mode Enfants : si le parent l'active/désactive, on re-filtre la liste.
    ParentalControls.instance.kidsMode.addListener(_onKidsModeChanged);
  }

  /// Re-filtre la liste courante quand le Mode Enfants bascule (sans toucher
  /// au réseau : on rejoue le dernier lot BRUT à travers le nouveau filtre).
  void _onKidsModeChanged() {
    if (mounted) _ingest(_rawLive);
  }

  @override
  void dispose() {
    TvActivity.leave();
    _ingestGen++; // annule un pré-calcul en cours
    _sub?.cancel();
    _favSub?.cancel();
    _trendSub?.cancel();
    _recentSub?.cancel();
    TrendingRepository.instance.stop();
    _syncTimer?.cancel();
    _catDebounce?.cancel();
    _recomputeDebounce?.cancel();
    _previewDebounce?.cancel();
    _previewCh.dispose();
    _catLabelMemo.clear();
    ParentalControls.instance.kidsMode.removeListener(_onKidsModeChanged);
    super.dispose();
  }

  // ----- État dérivé MÉMOÏSÉ (scalabilité grosses listes) -----
  // On NE recalcule PAS ces listes à chaque frame : seulement quand une source
  // change (chaînes, favoris, tendances, historique, catégorie). Indispensable
  // pour rester fluide même avec des dizaines/centaines de milliers de chaînes.
  List<Channel> _favCh = const <Channel>[];
  List<Channel> _trendCh = const <Channel>[];
  List<Channel> _recentCh = const <Channel>[];
  List<Channel> _forYouCh = const <Channel>[];
  List<String> _dispCats = const <String>[];
  List<Channel> _shownList = const <Channel>[];
  // Nombre de chaînes par VRAIE catégorie (compteur de la C-List). Construit en
  // UNE passe O(n) dans _ingest (pas par item de build) → la C-List affiche le
  // compteur sans rescanner _all à chaque ligne. Les pseudo-catégories
  // (Tendances/Favoris/…) comptent via la longueur de leur liste dérivée.
  Map<String, int> _realCatCounts = const <String, int>{};
  // Index id -> chaîne, construit UNE fois par changement de source (dans
  // _recompute), réutilisé par les récents et « dernière vue ». Évite des
  // scans O(n) répétés dans build() (jank sur les très grandes listes).
  Map<String, Channel> _byId = const <String, Channel>{};
  // Dernière chaîne vue (alimente le hero « Continuer »), calculée dans
  // _recompute (pas dans build).
  Channel? _lastWatchedCh;
  // Clé STABLE de la grille de chaînes. Quand le bandeau « Reprendre » apparaît
  // (au retour du lecteur), la mise en page passe de Row à Column → sans clé,
  // la grille serait RECRÉÉE et le défilement/focus repartiraient au début.
  // Avec cette GlobalKey, Flutter PRÉSERVE la grille (scroll + focus) : on
  // revient exactement là où on regardait, pour continuer à scroller.
  final GlobalKey _liveGridKey = GlobalKey();

  /// Recalcule TOUT l'état dérivé à partir des sources. Appelé UNIQUEMENT quand
  /// une source change — jamais dans build().
  void _recompute() {
    // Index id -> chaîne (réutilisé : récents + « dernière vue »). Construit
    // ICI (changement de source) et pas dans build() → zéro scan par frame.
    _byId = <String, Channel>{
      for (final Channel c in _all) c.id: c,
    };
    // Favoris (ordre playlist).
    _favCh = _favIds.isEmpty
        ? const <Channel>[]
        : _all
            .where((Channel c) => _favIds.contains(c.id))
            .toList(growable: false);
    // Récemment regardées (ordre historique).
    if (_recentIds.isEmpty || _all.isEmpty) {
      _recentCh = const <Channel>[];
    } else {
      _recentCh = <Channel>[
        for (final String id in _recentIds)
          if (_byId[id] != null) _byId[id]!,
      ];
    }
    // Tendances (ordre de popularité, match par nom insensible à la casse).
    if (_trending.isEmpty || _all.isEmpty || !_precomputed) {
      _trendCh = const <Channel>[]; // attend le pré-calcul (noms curés)
    } else {
      final Map<String, Channel> byName = <String, Channel>{};
      for (final Channel c in _all) {
        byName.putIfAbsent(c.cleanName.trim().toLowerCase(), () => c);
      }
      final List<Channel> out = <Channel>[];
      final Set<String> seen = <String>{};
      for (final String name in _trending) {
        final Channel? c = byName[name.trim().toLowerCase()];
        if (c != null && seen.add(c.id)) out.add(c);
      }
      _trendCh = out;
    }
    // « Pour vous » : petit MOTEUR DE RECO local (pas d'envoi de données). On
    // construit un PROFIL DE GOÛT pondéré depuis l'historique récent — genre ET
    // pays, pondérés par fréquence ET récence (la dernière vue pèse le plus) —
    // puis on SCORE chaque chaîne candidate (hors déjà-vues/favorites) par
    // affinité (genre ×2 + pays ×1) et on garde les meilleures. Calculé ICI
    // (O(n), une fois par changement de source — jamais en build).
    if (_recentIds.isEmpty || _all.isEmpty || !_precomputed) {
      _forYouCh = const <Channel>[]; // attend le pré-calcul (genre/pays)
    } else {
      final Map<ChannelGenre, double> genreScore = <ChannelGenre, double>{};
      final Map<String, double> countryScore = <String, double>{};
      int rank = 0;
      for (final String id in _recentIds.take(20)) {
        final Channel? c = _byId[id];
        if (c == null) continue;
        final double w = 1.0 / (1 + rank); // récence : poids décroissant
        rank++;
        if (c.genre != ChannelGenre.other) {
          genreScore[c.genre] = (genreScore[c.genre] ?? 0) + w;
        }
        final String? cc = c.country?.code;
        if (cc != null && cc.isNotEmpty) {
          countryScore[cc] = (countryScore[cc] ?? 0) + w;
        }
      }
      if (genreScore.isEmpty && countryScore.isEmpty) {
        _forYouCh = const <Channel>[];
      } else {
        final Set<String> exclude = <String>{..._recentIds, ..._favIds};
        final List<Channel> cand = <Channel>[];
        final Map<String, double> score = <String, double>{};
        for (final Channel c in _all) {
          if (exclude.contains(c.id)) continue;
          double s = 0;
          if (c.genre != ChannelGenre.other) {
            s += (genreScore[c.genre] ?? 0) * 2.0;
          }
          final String? cc = c.country?.code;
          if (cc != null) s += countryScore[cc] ?? 0;
          if (s > 0) {
            score[c.id] = s;
            cand.add(c);
          }
        }
        // Tri par affinité décroissante ; on garde le top 40.
        cand.sort((Channel a, Channel b) =>
            (score[b.id] ?? 0).compareTo(score[a.id] ?? 0));
        _forYouCh = cand.length > 40 ? cand.sublist(0, 40) : cand;
      }
    }
    // Catégories affichées (pseudo-catégories non vides en tête).
    final List<String> cats = <String>[];
    if (_trendCh.isNotEmpty) cats.add(_kTrendCat);
    if (_favCh.isNotEmpty) cats.add(_kFavCat);
    if (_recentCh.isNotEmpty) cats.add(_kRecentCat);
    if (_forYouCh.isNotEmpty) cats.add(_kForYouCat);
    cats.addAll(_cats);
    _dispCats = cats;
    // Grille affichée selon la catégorie sélectionnée (extraite : voir
    // _recomputeShown — c'est la SEULE partie qui dépend de _selectedCat).
    _recomputeShown();
    // Dernière chaîne vue (alimente le hero) — calculée ICI, pas en build.
    _lastWatchedCh = null;
    for (final String id in _recentIds) {
      final Channel? c = _byId[id];
      if (c != null) {
        _lastWatchedCh = c;
        break;
      }
    }
  }

  /// Recalcule UNIQUEMENT la grille affichée à partir de _selectedCat.
  ///
  /// ANTI-ANR (P0, logcat SHIELD « Waited 5000ms for KeyEvent », 100 % CPU) :
  /// changer de catégorie ne dépend QUE de _selectedCat — pas besoin de
  /// reconstruire _byId, la map de tendances (qui curait 50 000 noms),
  /// « Pour vous » ni la dernière vue. Avant, _select() relançait TOUT
  /// _recompute() → une tempête de RegExp à CHAQUE déplacement D-pad dans les
  /// catégories → fil UI figé ~3,7 s → ANR. Ici : une seule passe O(n) de
  /// filtre sur la catégorie BRUTE (trim, aucune curation) → instantané.
  void _recomputeShown() {
    if (_selectedCat == _kTrendCat) {
      _shownList = _trendCh;
    } else if (_selectedCat == _kFavCat) {
      _shownList = _favCh;
    } else if (_selectedCat == _kRecentCat) {
      _shownList = _recentCh;
    } else if (_selectedCat == _kForYouCat) {
      _shownList = _forYouCh;
    } else if (_selectedCat == null) {
      _shownList = _all;
    } else {
      _shownList = _all
          .where((Channel c) => _catOf(c) == _selectedCat)
          .toList(growable: false);
    }
  }

  /// Met à jour (débouncé) la chaîne reflétée par le hero quand une carte de la
  /// grille prend le focus. 120 ms → en défilement rapide, on ne lance pas une
  /// requête EPG par carte traversée, seulement à l'arrêt.
  /// Ouvre le lecteur pour [index] de la liste affichée, PUIS — au retour —
  /// DÉSIGNE la chaîne quittée pour que SA carte reprenne le focus. La grille
  /// (et donc la catégorie) ne bouge pas → on revient exactement où on était.
  Future<void> _openPlayerWith(List<Channel> list, int index,
      {required bool fromRail}) async {
    if (index < 0 || index >= list.length) return;
    final String chId = list[index].id;
    // On coupe l'aperçu AVANT d'ouvrir le plein écran (une seule connexion).
    setState(() => _playerOpen = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
    if (!mounted) return;
    setState(() {
      _playerOpen = false;
      _restoreFocusId = chId;
      _restoreFromRail = fromRail;
    });
  }

  Future<void> _openPlayer(int index) =>
      _openPlayerWith(_shownList, index, fromRail: false);

  void _setPreview(Channel c) {
    // Focuser une CHAÎNE annule tout changement de CATÉGORIE en attente : si un
    // focus transitoire avait effleuré une catégorie (ex. au retour du lecteur),
    // sa sélection débouncée ne se déclenchera pas → la catégorie ne « saute »
    // plus. (Placé AVANT le court-circuit pour s'appliquer même si la chaîne est
    // identique au précédent aperçu.)
    _catDebounce?.cancel();
    if (_previewCh.value?.id == c.id) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _previewCh.value?.id != c.id) {
        _previewCh.value = c; // seule la colonne de droite se reconstruit
      }
    });
  }

  /// Compteur affiché dans la C-List pour une catégorie (vraie ou pseudo).
  int _countOf(String cat) {
    if (cat == _kTrendCat) return _trendCh.length;
    if (cat == _kFavCat) return _favCh.length;
    if (cat == _kRecentCat) return _recentCh.length;
    if (cat == _kForYouCat) return _forYouCh.length;
    return _realCatCounts[cat] ?? 0;
  }

  /// Sélectionne une catégorie (focus/OK) puis recalcule SEULEMENT la grille
  /// (pas tout l'état dérivé — cf. _recomputeShown, anti-ANR).
  void _select(String cat) {
    if (_selectedCat == cat) return;
    setState(() {
      _selectedCat = cat;
      _recomputeShown();
    });
  }

  /// Coalesce les recalculs déclenchés par les flux (favoris/récents/tendances).
  /// Plusieurs émissions rapprochées → UN SEUL `_recompute` (anti-ANR). Le délai
  /// court (150 ms) reste imperceptible pour ces mises à jour non urgentes.
  void _scheduleRecompute() {
    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(_recompute);
    });
  }

  /// Sélection DÉBOUNCÉE (P1-5) : utilisée par le focus D-pad. On attend que le
  /// focus se pose ~220 ms avant le _recompute O(n) → plus de jank/ANR quand
  /// l'utilisateur traverse rapidement les catégories à la télécommande.
  void _selectDebounced(String cat) {
    if (_selectedCat == cat) return;
    _catDebounce?.cancel();
    _catDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _select(cat);
    });
  }


  /// Vrai pour les pseudo-catégories spéciales (teintées or).
  bool _isSpecialCat(String cat) =>
      cat == _kTrendCat ||
      cat == _kFavCat ||
      cat == _kRecentCat ||
      cat == _kForYouCat;

  /// Libellé visible d'une catégorie (les sentinelles sont traduites/ornées).
  // Libellés de catégories MÉMOÏSÉS : `_catLabel` passe par ~6 regex ; il est
  // appelé pour chaque ligne visible de la colonne des catégories À CHAQUE
  // build. Sans mémo, chaque rafraîchissement refaisait tout le nettoyage.
  final Map<String, String> _catLabelMemo = <String, String>{};

  String _catLabel(BuildContext context, String cat) {
    if (cat == _kTrendCat) return '🔥 Tendances';
    if (cat == _kFavCat) return '★ ${context.l10n.navFavorites}';
    if (cat == _kRecentCat) return '🕒 Récemment';
    if (cat == _kForYouCat) return '✨ Pour vous';
    // Catégorie réelle : on NETTOIE le libellé affiché (FR|/UK|, RAW, 60fps,
    // hevc…) via le curateur PARTAGÉ (appel en lecture seule, on ne le modifie
    // pas) + polissage TV. La clé brute (_catOf) reste INTACTE pour le filtrage.
    final String? hit = _catLabelMemo[cat];
    if (hit != null) return hit;
    final String pretty =
        _tvPretty(_tvStripCodec(TitleCurator.curateCategory(cat)));
    final String out = pretty.isEmpty ? cat : pretty;
    _catLabelMemo[cat] = out;
    return out;
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

  // Catégorie EXACTEMENT comme écrite dans la source (M3U group-title /
  // Xtream category_name). On ne reclasse PAS : on respecte l'ordre et les
  // noms du créateur de la playlist.
  static String _catOf(Channel c) {
    final String raw = c.category.trim();
    return raw.isEmpty ? 'Autres' : raw;
  }

  /// Vrai si la chaîne est classée « Adulte » (pour le Mode Enfants).
  /// IMPORTANT (stabilité) : on lit le genre DÉJÀ classé et MIS EN CACHE du
  /// modèle Channel (O(1) après 1er calcul). Avant, on re-classait via le
  /// classifieur complet (des dizaines de regex) à CHAQUE rafraîchissement —
  /// sur une grosse liste (10 000+ chaînes), ça figeait le thread UI → l'app
  /// « ne s'updatait plus » puis se fermait (ANR). Plus jamais.
  /// Mode Enfants SANS calcul lourd : on lit le genre EN CACHE uniquement.
  /// Pas encore calculé → on CACHE la chaîne (jamais d'adulte visible par
  /// erreur) ; elle réapparaît quand le pré-calcul termine (re-ingest).
  static bool _hideForKids(Channel c) {
    final ChannelGenre? g = ChannelPrecompute.cachedGenre(c);
    return g == null || g == ChannelGenre.adult;
  }

  void _ingest(List<Channel> channels) {
    // On garde la liste BRUTE pour pouvoir re-filtrer si le Mode Enfants change.
    _rawLive = channels;
    // MODE ENFANTS : on retire toutes les chaînes classées « Adulte ». Le filtre
    // ne s'applique QUE si le parent l'a activé (défaut : désactivé → aucun
    // changement). Détection via le classifieur existant (mots-clés robustes).
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<Channel> live = channels.where((Channel c) {
      if (!c.isLive) return false;
      if (kids && _hideForKids(c)) return false;
      return true;
    }).toList(growable: false);
    // Ordre des catégories = ordre d'APPARITION ; dédup via Set (O(1)) pour
    // rester rapide même sur de très grandes listes (évite un contains O(n²)).
    final List<String> cats = <String>[];
    final Set<String> seenCats = <String>{};
    // Compteur par catégorie calculé ICI, dans la MÊME passe O(n) (pas par ligne
    // de la C-List) → affichage du compteur sans rescanner _all.
    final Map<String, int> counts = <String, int>{};
    for (final Channel c in live) {
      final String cat = _catOf(c);
      if (seenCats.add(cat)) cats.add(cat);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _all = live;
      _cats = cats;
      _realCatCounts = counts;
      _selectedCat ??= cats.isNotEmpty ? cats.first : null;
      // On ne réinitialise PAS si l'utilisateur est sur une pseudo-catégorie
      // (Tendances/Favoris/Récemment, absente de `cats`) — sinon un refresh de
      // la source l'en ferait sortir.
      if (_selectedCat != null &&
          !_isSpecialCat(_selectedCat!) &&
          !seenCats.contains(_selectedCat)) {
        _selectedCat = cats.isNotEmpty ? cats.first : null;
      }
      _recompute();
    });
    _startPrecompute(channels);
  }

  /// Lance (ou relance) le pré-calcul en arrière-plan pour le lot BRUT reçu.
  /// Un nouveau lot annule le précédent (génération). À la fin : on rejoue
  /// _recompute (Tendances / Pour vous deviennent disponibles) et, en Mode
  /// Enfants, on re-filtre pour faire apparaître les chaînes non-adultes.
  void _startPrecompute(List<Channel> channels) {
    final int gen = ++_ingestGen;
    if (channels.every(ChannelPrecompute.isDone)) {
      _precomputed = true;
      return;
    }
    _precomputed = false;
    ChannelPrecompute.run(
      channels,
      cancelled: () => !mounted || gen != _ingestGen,
    ).then((_) {
      if (!mounted || gen != _ingestGen) return;
      _precomputed = true;
      if (ParentalControls.instance.kidsMode.value) {
        _ingest(_rawLive); // re-filtre avec les genres maintenant connus
      } else {
        _scheduleRecompute();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_all.isEmpty) {
      // États PRÉCIS au lieu d'un « écran mort » :
      //  • en cours / réseau → « Recherche de tes chaînes… »
      //  • source refusée     → identifiants invalides côté panel
      //  • rien d'assigné     → message d'activation habituel
      final bool searching = _syncing ||
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
                  // Visible ICI car l'écran d'activation ne s'affiche plus
                  // (déjà activé) : le client/revendeur a besoin de la MAC.
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
                                color: TvTokens.accentBright, spacing: 2)),
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

    // ===== DISPOSITION 3 COLONNES (façon box IPTV) =====
    //   gauche  : catégories (pleine hauteur)
    //   centre  : LISTE des chaînes (n° · logo · nom), focus = aperçu à droite
    //   droite  : aperçu vidéo (même moteur que le plein écran) + guide
    final Widget cList = _CategoryRail(
      cats: _dispCats,
      selectedCat: _selectedCat,
      // La liste des catégories ne PREND JAMAIS le focus initial / au retour
      // (sinon la 1re catégorie se sélectionnait toute seule en revenant du
      // lecteur). Le focus revient sur la LIGNE de chaîne quittée.
      autofocusFirst: false,
      fill: true,
      labelOf: (String c) => _catLabel(context, c),
      countOf: _countOf,
      onSelect: _select,
      onFocusDebounced: _selectDebounced,
    );

    final Widget list = _ChannelList(
      key: _liveGridKey,
      channels: _shownList,
      onFocused: _setPreview,
      onPlay: _openPlayer,
      restoreFocusId: _restoreFromRail ? null : _restoreFocusId,
      onRestored: () => _restoreFocusId = null,
    );

    // Chaîne prévisualisée : celle sous le focus, sinon la 1re de la liste.
    // ValueListenableBuilder : le changement de focus ne reconstruit QUE cette
    // colonne (cf. _previewCh).
    final Channel? first = _shownList.isNotEmpty ? _shownList.first : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 300, child: cList),
        const SizedBox(width: TvDimens.gutter),
        Expanded(child: list),
        const SizedBox(width: TvDimens.gutter),
        SizedBox(
          width: 470,
          child: ValueListenableBuilder<Channel?>(
            valueListenable: _previewCh,
            builder: (BuildContext context, Channel? pv, Widget? _) =>
                _PreviewPanel(channel: pv ?? first, suspended: _playerOpen),
          ),
        ),
      ],
    );
  }
}

/// C-LIST compacte (catégories) — bande HAUTE À DROITE.
///
/// Hauteur BORNÉE (≤ _kMaxVisible lignes puis scroll vertical interne) pour ne
/// jamais manger la place des chaînes. Chaque ligne : libellé (ellipsis) +
/// compteur ALIGNÉ À DROITE. Focusable D-pad (or au focus) ; le focus met à jour
/// la grille en DÉBOUNCÉ (pas de recalcul sur chaque ligne traversée).
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.cats,
    required this.selectedCat,
    required this.autofocusFirst,
    required this.labelOf,
    required this.countOf,
    required this.onSelect,
    required this.onFocusDebounced,
    this.fill = false,
  });

  /// `true` → la liste occupe TOUTE la hauteur disponible (colonne de gauche
  /// de la disposition 3 colonnes) au lieu d'être bornée à quelques lignes.
  final bool fill;

  final List<String> cats;
  final String? selectedCat;
  final bool autofocusFirst;
  final String Function(String) labelOf;
  final int Function(String) countOf;
  final void Function(String) onSelect;
  final void Function(String) onFocusDebounced;

  // Hauteur d'une ligne (itemExtent) et nombre de lignes visibles max : on
  // calcule une hauteur EXACTE (pas de shrinkWrap qui mesurerait des milliers de
  // catégories) → liste paresseuse, fluide même sur d'énormes playlists.
  static const double _kRowExtent = 46;
  static const int _kMaxVisible = 5;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) return const SizedBox.shrink();
    final int visible = cats.length < _kMaxVisible ? cats.length : _kMaxVisible;
    return Container(
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
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
          if (fill)
            Expanded(child: _buildList())
          else
            SizedBox(height: visible * _kRowExtent, child: _buildList()),
        ],
      ),
    );
  }

  /// Liste paresseuse des catégories (hauteur fixe par ligne → fluide même
  /// avec des milliers d'entrées).
  Widget _buildList() {
    return ListView.builder(
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
        builder: (BuildContext context, bool focused) {
          if (focused) onFocused();
          // FOCUS UNIQUE : seule la ligne RÉELLEMENT focus porte l'or. La
          // catégorie active-mais-pas-focus = gris discret (jamais d'or).
          final bool active = selected && !focused;
          final Color bg =
              (focused || active) ? TvTokens.sel : Colors.transparent;
          final Color fg = focused
              ? TvTokens.accentBright
              : (active ? TvTokens.text : TvTokens.muted);
          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: focused
                  ? Border.all(
                      color: TvTokens.accent, width: TvDimens.focusOutline)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        fontWeight: (focused || active)
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: fg),
                  ),
                ),
                const SizedBox(width: 10),
                // Compteur ALIGNÉ À DROITE.
                Text(
                  '$count',
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w700,
                      color: focused ? TvTokens.accentBright : TvTokens.mutedDim),
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
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('REPRENDRE',
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
          child: Row(
            children: <Widget>[
              _LogoChip(channel: c),
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
        ),
      ),
    );
  }
}

/// Hero « aperçu live » : reflète la chaîne SURVOLÉE dans la grille (ou la
/// dernière vue). Logo normalisé + pastille ● EN DIRECT + EPG « EN CE MOMENT ·
/// programme ». OK = lire cette chaîne (rôle « Continuer » quand c'est la
/// dernière vue). La requête EPG est faite UNE fois par chaîne (pas par carte).
class _LiveHero extends StatefulWidget {
  const _LiveHero(
      {required this.channel, required this.all, this.autofocus = false});
  final Channel channel;
  final List<Channel> all;
  final bool autofocus;

  @override
  State<_LiveHero> createState() => _LiveHeroState();
}

class _LiveHeroState extends State<_LiveHero> {
  late Future<EpgProgram?> _epg = _loadEpg();

  Future<EpgProgram?> _loadEpg() =>
      EpgRepository.instance.currentProgram(widget.channel.id);

  @override
  void didUpdateWidget(covariant _LiveHero old) {
    super.didUpdateWidget(old);
    // Nouvelle chaîne survolée → une (seule) nouvelle requête EPG.
    if (old.channel.id != widget.channel.id) {
      _epg = _loadEpg();
    }
  }

  void _play() {
    final int idx = widget.all.indexOf(widget.channel);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(
            channels: widget.all, startIndex: idx < 0 ? 0 : idx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Channel c = widget.channel;
    return TvFocusable(
      autofocus: widget.autofocus,
      scale: TvFocusScale.large,
      baseColor: TvTokens.card,
      onSelect: _play,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            // Logo normalisé (contain + padding) sur une tuile premium.
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: TvTokens.tile,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border: Border.all(color: TvTokens.tileBorder),
              ),
              padding: const EdgeInsets.all(14),
              child: _Logo(channel: c),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _LivePill(),
                  const SizedBox(height: 10),
                  Text(_tvPretty(c.cleanName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.headline,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.text)),
                  const SizedBox(height: 8),
                  // EPG « EN CE MOMENT · programme » (une requête par chaîne) ;
                  // repli sur la catégorie si pas d'EPG → jamais de ligne vide.
                  FutureBuilder<EpgProgram?>(
                    future: _epg,
                    builder: (BuildContext context,
                        AsyncSnapshot<EpgProgram?> snap) {
                      final EpgProgram? p = snap.data;
                      // FALLBACK (pas d'EPG) : on reste COMPACT — juste la
                      // catégorie (ou rien), jamais de grand vide.
                      if (p == null) {
                        final String cat = c.category.trim();
                        if (cat.isEmpty) return const SizedBox.shrink();
                        return Text(_tvPretty(cat),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.body,
                                color: TvTokens.muted));
                      }
                      // EPG dispo : titre + barre de progression + horaires
                      // (+ synopsis si présent).
                      final int now = DateTime.now().millisecondsSinceEpoch;
                      final int span = p.stopTime - p.startTime;
                      final double prog = span > 0
                          ? ((now - p.startTime) / span)
                              .clamp(0.0, 1.0)
                              .toDouble()
                          : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('EN CE MOMENT · ${p.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: TvDimens.body,
                                  fontWeight: FontWeight.w600,
                                  color: TvTokens.text)),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: SizedBox(
                                    height: 4,
                                    child: LinearProgressIndicator(
                                      value: prog,
                                      backgroundColor: TvTokens.line,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              TvTokens.accent),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(p.timeRangeShort,
                                  style: TextStyle(
                                      fontSize: TvDimens.label,
                                      color: TvTokens.mutedDim)),
                            ],
                          ),
                          if (p.description != null &&
                              p.description!.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(p.description!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: TvDimens.label,
                                    color: TvTokens.muted)),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastille « ● EN DIRECT » (rouge sobre) avec point qui PULSE (0.6→1.0, 1.5 s)
/// pour signaler la liveness. Animation minuscule (un point de 8 px) → coût nul.
class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = Tween<double>(begin: 0.6, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TvTokens.live.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: TvTokens.live, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 7),
          Text('EN DIRECT',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: TvTokens.live)),
        ],
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
      this.restoreFocusId,
      this.onRestored});
  final List<Channel> channels;

  /// Signale au parent quelle chaîne vient de prendre le focus (→ hero).
  final void Function(Channel)? onFocused;

  /// Lance le lecteur pour l'index donné (la navigation est gérée par l'écran,
  /// qui sait ensuite RENDRE le focus à la bonne carte au retour).
  final void Function(int index)? onPlay;

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
        // Cartes PAYSAGE ~16:9 (réf. design).
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: 196,
          crossAxisSpacing: TvDimens.gutter,
          mainAxisSpacing: TvDimens.gutter,
        ),
        itemCount: widget.channels.length,
        // Garde-fou index : aucun accès hors borne même si la liste change.
        itemBuilder: (BuildContext context, int i) {
          if (i < 0 || i >= widget.channels.length) {
            return const SizedBox.shrink();
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

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Channel channel = widget.channel;
    final bool fav = FavoritesRepository.instance.current.contains(channel.id);
    final _ParsedName p = _parseName(channel);
    // PREMIUM (réf. design) : on retire le jargon codec (RAW/HEVC/60FPS/VIP/LIVE)
    // qui faisait « IPTV brut » et on ne garde qu'UN chip qualité (4K/FHD/HD).
    final String? quality = p.badges
        .cast<String?>()
        .firstWhere((String? b) => b == '4K' || b == 'FHD' || b == 'HD',
            orElse: () => null);
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
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // LOGO PETIT en chip haut-gauche (normalisé) : quand des chaînes
          // partagent le même logo, c'est le NOM qui distingue (réf. design).
          Positioned(top: 10, left: 10, child: _LogoChip(channel: channel)),
          // Chip qualité discret en haut-droite.
          if (quality != null)
            Positioned(top: 12, right: 12, child: _TagBadge(label: quality)),
          // Favori discret en bas-droite.
          if (fav)
            const Positioned(
              right: 12,
              bottom: 12,
              child:
                  Icon(Icons.favorite_rounded, size: 16, color: TvTokens.accent),
            ),
          // NOM DOMINANT en bas-gauche : c'est lui qui « porte » la carte.
          Positioned(
            left: 14,
            right: 40,
            bottom: 12,
            child: Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 22,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
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
    // Garde-fou mémoire LARGE : à 4000 le mémo se vidait en plein défilement
    // d'une grosse liste et chaque ligne repassait par les regex. 60 000 entrées
    // ≈ quelques Mo, couvre le plafond de chaînes chargées en mémoire.
    if (_nameMemo.length > 60000) _nameMemo.clear();
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: TvTokens.badgeBg,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: TvTokens.accent)),
    );
  }
}

/// Logo PETIT en chip (haut-gauche de la carte) : taille NORMALISÉE pour que
/// tous les logos pèsent visuellement pareil (jamais un logo qui remplit la
/// carte à côté d'un mini-logo). Réutilise [_Logo] (contain + repli initiales).
class _LogoChip extends StatelessWidget {
  const _LogoChip({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xD9141210), // rgba(20,18,16,.85)
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TvTokens.line),
      ),
      padding: const EdgeInsets.all(7),
      child: _Logo(channel: channel),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    // Repli PARESSEUX : `initials` (regex + split) n'est calculé que si le logo
    // manque ou échoue — pas pour chaque ligne qui a un logo.
    Widget fallback() => Center(
          child: Text(channel.initials,
              style: TextStyle(
                  fontSize: TvDimens.title,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.muted)),
        );
    final String? url = channel.logoUrl;
    if (url == null || url.isEmpty) return fallback();
    // CACHE DISQUE + mémoire (cached_network_image) : après le 1er affichage,
    // les logos s'affichent INSTANTANÉMENT — même après un redémarrage — et ne
    // se RE-TÉLÉCHARGENT jamais. C'est ce qui donne le scroll fluide « façon
    // Netflix » sur 20 000 chaînes (avant : Image.network re-téléchargeait à
    // chaque fois → flashs + jank). Skeleton discret (initiales 35 %) au lieu
    // d'un spinner (20 000 spinners = lag).
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => Opacity(opacity: 0.35, child: fallback()),
      errorWidget: (_, __, ___) => fallback(),
      // Décodage borné à 2× la taille AFFICHÉE (chip 48 px, écran rendu ≤ 1,5×)
      // → 4× moins de mémoire par logo qu'à 200 px, rendu identique à l'œil.
      memCacheWidth: 96,
      memCacheHeight: 96,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),
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
        final Color fg = focused ? TvTokens.onAccent : TvTokens.accentBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.sel,
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

// =========================================================
//  DISPOSITION 3 COLONNES — colonne CENTRALE : liste des chaînes
// =========================================================

/// Liste verticale des chaînes (n° · logo · nom · chip qualité), virtualisée.
/// Même contrat que l'ancienne grille : `onFocused` (→ aperçu), `onPlay`
/// (→ plein écran) et restauration du focus au retour du lecteur.
class _ChannelList extends StatelessWidget {
  const _ChannelList(
      {super.key,
      required this.channels,
      this.onFocused,
      this.onPlay,
      this.restoreFocusId,
      this.onRestored});
  final List<Channel> channels;
  final void Function(Channel)? onFocused;
  final void Function(int index)? onPlay;
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  static const double _kRowExtent = 64;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoChannelInCategory,
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemExtent: _kRowExtent,
        itemCount: channels.length,
        itemBuilder: (BuildContext context, int i) => _ChannelRow(
          channel: channels[i],
          index: i,
          autofocus: i == 0 && restoreFocusId == null,
          onFocused: onFocused,
          onPlay: onPlay,
          restoreFocusId: restoreFocusId,
          onRestored: onRestored,
        ),
      ),
    );
  }
}

/// Une ligne de chaîne : numéro · logo · nom (+ chip 4K/FHD/HD).
class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    required this.channel,
    required this.index,
    this.autofocus = false,
    this.onFocused,
    this.onPlay,
    this.restoreFocusId,
    this.onRestored,
  });
  final Channel channel;
  final int index;
  final bool autofocus;
  final void Function(Channel)? onFocused;
  final void Function(int index)? onPlay;
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  // Node possédé par la ligne : nécessaire pour RE-DEMANDER le focus au retour
  // du lecteur (TvFocusable ne dispose pas un node qu'il n'a pas créé).
  final FocusNode _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Channel channel = widget.channel;
    // Analyse du nom (badges 4K/FHD/HD) : helper statique mémoïsé partagé avec
    // la carte de grille — on l'appelle par sa classe.
    final _ParsedName p = _ChannelCardState._parseName(channel);
    final String? quality = p.badges
        .cast<String?>()
        .firstWhere((String? b) => b == '4K' || b == 'FHD' || b == 'HD',
            orElse: () => null);
    if (widget.restoreFocusId != null && widget.restoreFocusId == channel.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.channel.id) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TvFocusable(
        focusNode: _node,
        autofocus: widget.autofocus,
        scale: TvFocusScale.small,
        baseColor: Colors.transparent,
        onFocusChange: (bool f) {
          if (f) widget.onFocused?.call(channel);
        },
        onSelect: () => widget.onPlay?.call(widget.index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                child: Text('${widget.index + 1}',
                    textAlign: TextAlign.right,
                    style: TvTokens.mono(15, color: TvTokens.mutedDim)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                  width: 48, height: 48, child: _LogoChip(channel: channel)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(19,
                        weight: FontWeight.w600, color: TvTokens.text)),
              ),
              if (quality != null) ...<Widget>[
                const SizedBox(width: 10),
                _TagBadge(label: quality),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  DISPOSITION 3 COLONNES — colonne DROITE : aperçu vidéo + guide
// =========================================================

/// Aperçu vidéo (16:9) de la chaîne focalisée + « Maintenant / À suivre ».
/// `suspended` = plein écran ouvert → l'aperçu est retiré (flux fermé).
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.channel, required this.suspended});
  final Channel? channel;
  final bool suspended;

  @override
  Widget build(BuildContext context) {
    final Channel? c = channel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 16 / 9,
          child: (c == null || suspended)
              ? Container(
                  decoration: BoxDecoration(
                    color: TvTokens.tile,
                    borderRadius: BorderRadius.circular(TvTokens.rCard),
                    border: Border.all(color: TvTokens.lineSoft),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.live_tv_rounded,
                      size: 56, color: TvTokens.mutedDim),
                )
              : TvLivePreview(channel: c),
        ),
        const SizedBox(height: 14),
        if (c != null) _PreviewInfo(channel: c),
      ],
    );
  }
}

/// Nom de la chaîne + programme en cours (barre de progression) + suivant.
class _PreviewInfo extends StatefulWidget {
  const _PreviewInfo({required this.channel});
  final Channel channel;
  @override
  State<_PreviewInfo> createState() => _PreviewInfoState();
}

class _PreviewInfoState extends State<_PreviewInfo> {
  late Future<List<EpgProgram?>> _epg = _load();

  Future<List<EpgProgram?>> _load() => Future.wait(<Future<EpgProgram?>>[
        EpgRepository.instance.currentProgram(widget.channel.id),
        EpgRepository.instance.nextProgram(widget.channel.id),
      ]);

  @override
  void didUpdateWidget(covariant _PreviewInfo old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) _epg = _load();
  }

  String _hm(int ms) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Channel c = widget.channel;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_tvPretty(c.cleanName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.display(22, color: TvTokens.text)),
          const SizedBox(height: 10),
          FutureBuilder<List<EpgProgram?>>(
            future: _epg,
            builder: (BuildContext context,
                AsyncSnapshot<List<EpgProgram?>> snap) {
              final EpgProgram? now =
                  (snap.data != null && snap.data!.isNotEmpty) ? snap.data![0] : null;
              final EpgProgram? next =
                  (snap.data != null && snap.data!.length > 1) ? snap.data![1] : null;
              if (now == null) {
                final String cat = c.category.trim();
                return Text(cat.isEmpty ? context.l10n.tvNavLive : _tvPretty(cat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(15, color: TvTokens.muted));
              }
              final int nowMs = DateTime.now().millisecondsSinceEpoch;
              final int span = now.stopTime - now.startTime;
              final double prog = span > 0
                  ? ((nowMs - now.startTime) / span).clamp(0.0, 1.0)
                  : 0.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.l10n.tvEpgNow.toUpperCase(),
                      style: TvTokens.ui(11,
                          weight: FontWeight.w700,
                          color: TvTokens.accentBright,
                          spacing: 2)),
                  const SizedBox(height: 4),
                  Text(now.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(17,
                          weight: FontWeight.w600, color: TvTokens.text)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(TvTokens.rSmall),
                    child: LinearProgressIndicator(
                      value: prog,
                      minHeight: 4,
                      backgroundColor: TvTokens.line,
                      color: TvTokens.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${_hm(now.startTime)} – ${_hm(now.stopTime)}',
                      style: TvTokens.ui(13, color: TvTokens.mutedDim)),
                  if (next != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(context.l10n.tvEpgNext.toUpperCase(),
                        style: TvTokens.ui(11,
                            weight: FontWeight.w700,
                            color: TvTokens.mutedDim,
                            spacing: 2)),
                    const SizedBox(height: 4),
                    Text('${_hm(next.startTime)}  ${next.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(15, color: TvTokens.muted)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
