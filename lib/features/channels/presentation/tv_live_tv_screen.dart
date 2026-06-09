// =========================================================
//  tv_live_tv_screen.dart — Écran « DIRECT / LIVE TV »
// =========================================================
//  Disposition « box IPTV / IBO » en 10-foot UI, pilotée 100 % à la
//  télécommande, avec un VRAI aperçu vidéo EN DIRECT à droite pendant
//  qu'on parcourt les chaînes à gauche. L'écran est partagé en deux :
//
//    ZONE GAUCHE (~40 %) — navigateur de chaînes
//      • une colonne « catégories / groupes » à l'extrême gauche ;
//      • un en-tête : nom de la catégorie + compteur de position
//        (ex. « FR| CINÉMA HD/4K (2 / 40) ») ;
//      • la liste verticale des chaînes, en colonnes alignées :
//        [numéro]  [logo]  [nom] ;
//      • la ligne FOCUSÉE est surlignée d'une barre pleine couleur
//        d'accent (focus ring net, lisible à 3 m) ;
//      • un pied de zone avec la ligne d'aide
//        (« Appui long sur OK = favoris »).
//
//    ZONE DROITE (~60 %) — aperçu LIVE
//      • lecture EN DIRECT de la chaîne sélectionnée (le vrai flux qui
//        tourne, pas une image figée), via media_kit + le mini-relais
//        local (1 connexion, comme le lecteur plein écran) ;
//      • overlay bas : nom de la chaîne, programme EPG en cours + barre
//        de progression, et bouton « Recherche » en bas à droite.
//
//  COMPORTEMENTS TÉLÉCOMMANDE
//    Haut / Bas      : parcourt les chaînes (ou les catégories selon la
//                      colonne active) ; l'aperçu se met à jour avec un
//                      léger DEBOUNCE pour ne pas relancer un flux à
//                      chaque cran.
//    Gauche / Droite : bascule entre la colonne catégories et la liste.
//    OK (appui court): passe la chaîne en PLEIN ÉCRAN (lecteur complet).
//    OK (appui long) : ajoute / retire des favoris.
//    Retour          : revient à l'accueil.
//
//  RÉUTILISATION (consigne projet) : on NE réécrit ni le parsing, ni le
//  moteur de lecture, ni l'EPG. On s'appuie sur :
//    - PlaylistRepository (chaînes déjà parsées en base) ;
//    - LocalStreamRelay + media_kit (même pile que le lecteur existant) ;
//    - EpgRepository (programme en cours) ;
//    - FavoritesRepository (favoris) ;
//    - playChannel() (ouverture plein écran identique au reste de l'app).
//
//  i18n : cet écran utilise des libellés FR en clair (produit FR-first)
//  plutôt que des clés AppLocalizations, pour rester DÉCOUPLÉ du
//  générateur gen-l10n (un libellé manquant dans un .arb casserait la
//  compilation). Les libellés sont regroupés en tête de classe pour
//  faciliter une future extraction l10n.
// =========================================================

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/tv_palette.dart';
import '../../../core/widgets/tv_accent_scope.dart';
import '../../../core/widgets/tv_route.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../player/data/local_stream_relay.dart';
import '../../player/data/player_settings.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'search_screen.dart';
import 'widgets/channel_logo.dart';
import 'widgets/empty_state.dart';
import 'widgets/source_choice_sheet.dart';

/// Colonne active (celle que la télécommande pilote). On bascule entre
/// elles avec Gauche/Droite : catégories ◄► liste de chaînes ◄► aperçu
/// (où OK déclenche la Recherche).
enum _Pane { categories, channels, preview }

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  // ----- Libellés FR (voir note i18n en tête de fichier) -----
  static const String _kFooterHint = 'Appui long sur OK = favoris  ·  '
      '◄ ► change de colonne  ·  OK = plein écran';
  static const String _kSearchLabel = 'Recherche';
  static const String _kCategoriesTitle = 'Catégories';
  static const String _kNoProgram = 'Programme non disponible';

  // ----- Données dérivées de la base -----
  /// Catégories ordonnées (ordre d'apparition dans la playlist).
  List<String> _categories = <String>[];

  /// Chaînes regroupées par catégorie BRUTE (group-title M3U /
  /// category_name Xtream), pour coller à l'affichage type box IPTV
  /// (« FR| CINÉMA HD/4K »).
  Map<String, List<Channel>> _byCategory = <String, List<Channel>>{};

  // ----- État de navigation -----
  _Pane _pane = _Pane.channels;
  int _catIndex = 0;
  int _chanIndex = 0;

  // ----- Aperçu vidéo (media_kit) -----
  late final Player _preview;
  late final VideoController _previewController;

  /// Chaîne actuellement CHARGÉE dans l'aperçu (peut différer de la
  /// chaîne sélectionnée tant que le debounce n'a pas déclenché).
  Channel? _previewChannel;

  /// Debounce : on n'ouvre le flux d'aperçu qu'après une courte pause
  /// sans changement de sélection — sinon on relancerait un flux à
  /// chaque cran du D-pad (saccades + martèlement du serveur IPTV).
  Timer? _previewDebounce;
  static const Duration _kPreviewDebounce = Duration(milliseconds: 650);

  // ----- EPG -----
  EpgProgram? _currentProgram;
  Timer? _epgTicker; // rafraîchit la barre de progression
  int _epgRequestToken = 0; // anti-course (réponses EPG hors d'ordre)

  // ----- Favoris -----
  Set<String> _favorites = <String>{};
  StreamSubscription<Set<String>>? _favSub;

  // ----- Appui long OK (favoris) vs appui court (plein écran) -----
  Timer? _okLongPressTimer;
  bool _okConsumedByLongPress = false;
  static const Duration _kLongPress = Duration(milliseconds: 450);

  // ----- Scroll auto pour garder la sélection visible -----
  final ScrollController _catScroll = ScrollController();
  final ScrollController _chanScroll = ScrollController();
  static const double _kRowExtent = 64; // hauteur d'une ligne chaîne
  static const double _kCatRowExtent = 56; // hauteur d'une ligne catégorie

  // Abonnement aux changements de chaînes (ajout / refresh de source).
  StreamSubscription<List<Channel>>? _channelsSub;

  final FocusNode _focusNode = FocusNode(debugLabel: 'live-tv-root');

  @override
  void initState() {
    super.initState();

    // Aperçu : buffer modeste pour un démarrage rapide à chaque zap
    // (on n'a pas besoin du gros matelas anti-coupure du plein écran).
    _preview = Player(
      configuration: PlayerConfiguration(
        bufferSize: 8 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _previewController = VideoController(_preview);
    _applyPreviewMpvOptions();

    // Charge les réglages lecteur (User-Agent) pour l'aperçu.
    PlayerSettings.instance.load();

    // Favoris : état initial + abonnement réactif.
    FavoritesRepository.instance.initialize();
    _favorites = <String>{...FavoritesRepository.instance.current};
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> f) {
      if (mounted) setState(() => _favorites = <String>{...f});
    });

    // Snapshot initial des chaînes + abonnement aux mises à jour.
    _rebuildIndex(PlaylistRepository.instance.currentChannels);
    _channelsSub =
        PlaylistRepository.instance.channelsStream.listen((List<Channel> chans) {
      if (!mounted) return;
      _rebuildIndex(chans);
      setState(() {});
    });

    // Rafraîchit la barre de progression EPG toutes les 20 s.
    _epgTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });

    // Lance l'aperçu de la première chaîne après le 1er frame (le relais
    // a besoin que l'app soit prête ; on évite aussi un setState pendant
    // l'initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final Channel? first = _selectedChannel;
      if (first != null) _schedulePreview(immediate: true);
    });
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _epgTicker?.cancel();
    _okLongPressTimer?.cancel();
    _favSub?.cancel();
    _channelsSub?.cancel();
    _catScroll.dispose();
    _chanScroll.dispose();
    _focusNode.dispose();
    _preview.dispose();
    super.dispose();
  }

  // ============================================================
  //  Indexation des chaînes par catégorie
  // ============================================================

  /// (Re)construit `_categories` + `_byCategory` à partir d'une liste
  /// plate de chaînes, en préservant l'ordre d'apparition. On essaie de
  /// conserver la sélection courante (même catégorie / même chaîne) après
  /// un refresh pour ne pas « sauter » sous les doigts de l'utilisateur.
  void _rebuildIndex(List<Channel> all) {
    final String? keepCat =
        (_catIndex >= 0 && _catIndex < _categories.length)
            ? _categories[_catIndex]
            : null;
    final String? keepChanId = _selectedChannel?.id;

    final LinkedHashMap<String, List<Channel>> map =
        LinkedHashMap<String, List<Channel>>();
    for (final Channel c in all) {
      // On regroupe TOUTES les chaînes de la playlist active par catégorie
      // brute (group-title M3U / category_name Xtream). On ne filtre pas
      // sur le flag `isLive` : en IPTV il est souvent mal renseigné, et le
      // filtrer priverait l'écran de chaînes parfaitement valides.
      final String cat = c.category.trim().isEmpty ? 'Autres' : c.category.trim();
      map.putIfAbsent(cat, () => <Channel>[]).add(c);
    }

    _byCategory = map;
    _categories = map.keys.toList(growable: false);

    // Restaure la position si possible.
    if (keepCat != null && _categories.contains(keepCat)) {
      _catIndex = _categories.indexOf(keepCat);
    } else {
      _catIndex = _categories.isEmpty ? 0 : _catIndex.clamp(0, _categories.length - 1);
    }
    final List<Channel> chans = _currentCategoryChannels;
    if (keepChanId != null) {
      final int idx = chans.indexWhere((Channel c) => c.id == keepChanId);
      _chanIndex = idx >= 0 ? idx : 0;
    } else {
      _chanIndex = chans.isEmpty ? 0 : _chanIndex.clamp(0, chans.length - 1);
    }
  }

  List<Channel> get _currentCategoryChannels {
    if (_categories.isEmpty) return const <Channel>[];
    final String cat = _categories[_catIndex.clamp(0, _categories.length - 1)];
    return _byCategory[cat] ?? const <Channel>[];
  }

  Channel? get _selectedChannel {
    final List<Channel> chans = _currentCategoryChannels;
    if (chans.isEmpty) return null;
    return chans[_chanIndex.clamp(0, chans.length - 1)];
  }

  // ============================================================
  //  Aperçu vidéo
  // ============================================================

  /// Programme (debounced) l'ouverture du flux de la chaîne sélectionnée
  /// dans l'aperçu. `immediate` force l'ouverture sans attendre (premier
  /// affichage / retour de plein écran).
  void _schedulePreview({bool immediate = false}) {
    _previewDebounce?.cancel();
    if (immediate) {
      _openPreview();
      return;
    }
    _previewDebounce = Timer(_kPreviewDebounce, _openPreview);
  }

  Future<void> _openPreview() async {
    final Channel? ch = _selectedChannel;
    if (ch == null) return;
    // Déjà chargée → rien à faire (évite un re-open redondant).
    if (_previewChannel?.id == ch.id) return;
    _previewChannel = ch;

    // Charge le programme EPG en cours (anti-course via token).
    _loadEpgFor(ch);

    try {
      // Même chemin que le lecteur plein écran : on passe par le mini-
      // relais local (1 seule connexion vers le serveur IPTV, partagée
      // si on ouvre ensuite le plein écran sur la même chaîne).
      final String localUrl =
          await LocalStreamRelay.instance.playUrlFor(ch.streamUrl);
      if (!mounted || _previewChannel?.id != ch.id) return;
      await _preview.open(Media(localUrl));
    } catch (_) {
      // Repli : lecture directe si le relais ne démarre pas.
      if (!mounted || _previewChannel?.id != ch.id) return;
      try {
        await _preview.open(Media(ch.streamUrl));
      } catch (_) {
        // On n'affiche pas d'erreur bloquante dans l'aperçu : la zone
        // gauche reste pleinement navigable même si un flux refuse.
      }
    }
  }

  Future<void> _loadEpgFor(Channel ch) async {
    final int token = ++_epgRequestToken;
    setState(() => _currentProgram = null);
    try {
      final EpgProgram? prog =
          await EpgRepository.instance.currentProgram(ch.id);
      if (!mounted || token != _epgRequestToken) return;
      setState(() => _currentProgram = prog);
    } catch (_) {
      // EPG optionnel — on ignore silencieusement.
    }
  }

  /// Options libmpv minimales pour un aperçu stable (User-Agent du
  /// fournisseur + reconnexion auto). On reste léger : pas le gros
  /// matelas anti-coupure du plein écran.
  Future<void> _applyPreviewMpvOptions() async {
    try {
      // ignore: invalid_use_of_protected_member
      final dynamic native = (_preview.platform as dynamic);
      await native?.setProperty('cache', 'yes');
      await native?.setProperty('network-timeout', '30');
      await native?.setProperty('keep-open', 'yes');
      await native?.setProperty(
        'user-agent',
        PlayerSettings.instance.userAgent,
      );
      await native?.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=20,'
            'reconnect_on_http_error=4xx,5xx',
      );
    } catch (_) {
      // Plateforme sans surface native exposée → on garde les défauts.
    }
  }

  // ============================================================
  //  Navigation télécommande
  // ============================================================

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey k = event.logicalKey;
    final bool isSelect = k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA;

    // ----- Gestion fine de OK -----
    if (isSelect) {
      // En colonne APERÇU : OK = ouvrir la Recherche (pas d'appui long).
      if (_pane == _Pane.preview) {
        if (event is KeyDownEvent) _openSearch();
        return KeyEventResult.handled;
      }
      // Sinon : appui court = plein écran, appui long = favori.
      if (event is KeyDownEvent) {
        // Démarre le minuteur d'appui long. Si l'utilisateur maintient
        // OK ≥ 450 ms, on bascule en « ajout/retrait favori ».
        _okConsumedByLongPress = false;
        _okLongPressTimer?.cancel();
        _okLongPressTimer = Timer(_kLongPress, () {
          _okConsumedByLongPress = true;
          _toggleFavorite();
        });
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _okLongPressTimer?.cancel();
        // Relâché AVANT le seuil long → appui court = plein écran.
        if (!_okConsumedByLongPress) {
          _openFullscreen();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // Les déplacements ne se traitent que sur l'appui (pas le relâché),
    // mais on accepte la répétition (maintien) pour scroller en continu.
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.arrowUp) {
      if (_pane != _Pane.preview) _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_pane != _Pane.preview) _move(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _paneLeft();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _paneRight();
      return KeyEventResult.handled;
    }
    // Channel +/- de la télécommande : zappe les chaînes même depuis la
    // colonne catégories (raccourci attendu sur une box IPTV).
    if (k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (_pane != _Pane.channels) _pane = _Pane.channels;
      _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.mediaTrackNext) {
      if (_pane != _Pane.channels) _pane = _Pane.channels;
      _move(1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Déplace la sélection de [delta] dans la colonne active.
  void _move(int delta) {
    if (_pane == _Pane.categories) {
      if (_categories.isEmpty) return;
      final int next = (_catIndex + delta).clamp(0, _categories.length - 1);
      if (next == _catIndex) return;
      setState(() {
        _catIndex = next;
        _chanIndex = 0; // nouvelle catégorie → on repart en tête de liste
      });
      _ensureCatVisible();
      _ensureChanVisible();
      // Aperçu de la 1ʳᵉ chaîne de la catégorie survolée (debounced).
      _schedulePreview();
    } else {
      final List<Channel> chans = _currentCategoryChannels;
      if (chans.isEmpty) return;
      final int next = (_chanIndex + delta).clamp(0, chans.length - 1);
      if (next == _chanIndex) return;
      setState(() => _chanIndex = next);
      _ensureChanVisible();
      _schedulePreview();
    }
  }

  /// Gauche : aperçu → liste → catégories (bute à gauche).
  void _paneLeft() {
    final _Pane next = switch (_pane) {
      _Pane.preview => _Pane.channels,
      _Pane.channels => _Pane.categories,
      _Pane.categories => _Pane.categories,
    };
    if (next != _pane) setState(() => _pane = next);
  }

  /// Droite : catégories → liste → aperçu (bute à droite).
  void _paneRight() {
    final _Pane next = switch (_pane) {
      _Pane.categories => _Pane.channels,
      _Pane.channels => _Pane.preview,
      _Pane.preview => _Pane.preview,
    };
    if (next != _pane) setState(() => _pane = next);
  }

  /// OK appui court → plein écran (lecteur complet), puis reprise de
  /// l'aperçu au retour. On STOPPE l'aperçu pendant le plein écran pour
  /// ne pas décoder deux flux en parallèle.
  Future<void> _openFullscreen() async {
    final Channel? ch = _selectedChannel;
    if (ch == null) return;
    _previewDebounce?.cancel();
    await _preview.stop();
    _previewChannel = null;
    if (!mounted) return;
    await playChannel(context, ch, zapPlaylist: _currentCategoryChannels);
    // De retour du plein écran → on relance l'aperçu de la chaîne courante.
    if (mounted) _schedulePreview(immediate: true);
  }

  void _toggleFavorite() {
    final Channel? ch = _selectedChannel;
    if (ch == null) return;
    FavoritesRepository.instance.toggle(ch.id);
    // Retour visuel immédiat (le stream confirmera derrière).
    final bool nowFav = !_favorites.contains(ch.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
          backgroundColor: TvRoyal.surfaceHigh,
          content: Text(
            nowFav
                ? '★  ${ch.cleanName} ajoutée aux favoris'
                : '☆  ${ch.cleanName} retirée des favoris',
            style: AppTextStyles.bodyLarge,
          ),
        ));
    }
  }

  // Garde la ligne sélectionnée bien visible dans sa liste.
  void _ensureChanVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chanScroll.hasClients) return;
      _centerOn(_chanScroll, _chanIndex, _kRowExtent);
    });
  }

  void _ensureCatVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_catScroll.hasClients) return;
      _centerOn(_catScroll, _catIndex, _kCatRowExtent);
    });
  }

  void _centerOn(ScrollController ctrl, int index, double extent) {
    final double viewport = ctrl.position.viewportDimension;
    final double target =
        (index * extent) - (viewport / 2) + (extent / 2);
    final double clamped =
        target.clamp(0.0, ctrl.position.maxScrollExtent);
    ctrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _openSearch() {
    Navigator.of(context).push<void>(tvRoute<void>(const SearchScreen()));
  }

  // ============================================================
  //  UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // On (re)pose l'identité violette TV au cas où l'écran serait poussé
    // sans `tvRoute` (défense en profondeur — sans coût si déjà posée).
    return TvAccentScope(
      focusBorderColor: TvRoyal.accent,
      focusGlow: TvRoyal.focusGlow(),
      child: Scaffold(
        backgroundColor: TvRoyal.background,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: TvRoyal.backgroundGradient,
            ),
            child: SafeArea(
              child: _categories.isEmpty
                  ? EmptyStateView(
                      onAddPlaylist: () => showSourceChoiceSheet(context),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // ZONE GAUCHE — navigateur (≈ 40 %)
                        Expanded(
                          flex: 40,
                          child: _buildLeftZone(),
                        ),
                        // ZONE DROITE — aperçu live (≈ 60 %)
                        Expanded(
                          flex: 60,
                          child: _buildRightZone(),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ----- Zone gauche : colonne catégories + liste de chaînes -----

  Widget _buildLeftZone() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Colonne CATÉGORIES (largeur fixe, lisible à 3 m).
          SizedBox(
            width: 240,
            child: _buildCategoriesColumn(),
          ),
          const SizedBox(width: 14),
          // Liste des CHAÎNES (en-tête + liste + pied d'aide).
          Expanded(child: _buildChannelList()),
        ],
      ),
    );
  }

  Widget _buildCategoriesColumn() {
    final bool active = _pane == _Pane.categories;
    return Container(
      decoration: BoxDecoration(
        color: TvRoyal.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? TvRoyal.accent.withValues(alpha: 0.55) : TvRoyal.border,
          width: active ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              _kCategoriesTitle.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: TvRoyal.textTertiary,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _catScroll,
              itemExtent: _kCatRowExtent,
              physics: const ClampingScrollPhysics(),
              itemCount: _categories.length,
              itemBuilder: (BuildContext context, int i) {
                final String cat = _categories[i];
                final int count = _byCategory[cat]?.length ?? 0;
                final bool selected = i == _catIndex;
                return _CategoryRow(
                  label: cat,
                  count: count,
                  selected: selected,
                  paneActive: active,
                  onTap: () {
                    setState(() {
                      _pane = _Pane.categories;
                      _catIndex = i;
                      _chanIndex = 0;
                    });
                    _ensureChanVisible();
                    _schedulePreview();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList() {
    final List<Channel> chans = _currentCategoryChannels;
    final String cat =
        _categories.isEmpty ? '' : _categories[_catIndex.clamp(0, _categories.length - 1)];
    final bool active = _pane == _Pane.channels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // En-tête : « FR| CINÉMA HD/4K (2 / 40) »
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  cat,
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 22),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                chans.isEmpty ? '(0)' : '(${_chanIndex + 1} / ${chans.length})',
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 18,
                  color: TvRoyal.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Liste scrollable
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: TvRoyal.surface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? TvRoyal.accent.withValues(alpha: 0.55) : TvRoyal.border,
                width: active ? 1.6 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: chans.isEmpty
                ? Center(
                    child: Text(
                      'Aucune chaîne dans cette catégorie',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: TvRoyal.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _chanScroll,
                    itemExtent: _kRowExtent,
                    physics: const ClampingScrollPhysics(),
                    itemCount: chans.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Channel c = chans[i];
                      final bool selected = i == _chanIndex;
                      return _ChannelRow(
                        number: i + 1,
                        channel: c,
                        selected: selected,
                        paneActive: active,
                        isFavorite: _favorites.contains(c.id),
                        onTap: () {
                          setState(() {
                            _pane = _Pane.channels;
                            _chanIndex = i;
                          });
                          _schedulePreview();
                        },
                      );
                    },
                  ),
          ),
        ),

        // Pied de zone : ligne d'aide télécommande.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            _kFooterHint,
            style: AppTextStyles.labelSmall.copyWith(
              color: TvRoyal.textTertiary,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ----- Zone droite : aperçu live + overlay EPG -----

  Widget _buildRightZone() {
    final Channel? ch = _selectedChannel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: TvRoyal.voidSurface,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 1) La vidéo en direct (remplit toute la zone).
              Video(
                controller: _previewController,
                controls: (VideoState _) => const SizedBox.shrink(),
                fit: BoxFit.cover,
              ),

              // 2) Voile bas pour poser l'overlay texte.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: TvRoyal.heroScrim),
                ),
              ),

              // 3) Overlay info bas : nom + EPG + progression + recherche.
              if (ch != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 22,
                  child: _buildPreviewOverlay(ch),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewOverlay(Channel ch) {
    final EpgProgram? prog = _currentProgram;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            // Logo + nom de la chaîne.
            ChannelLogo(channel: ch, size: ChannelLogoSize.compact),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    ch.cleanName,
                    style: AppTextStyles.displayLarge.copyWith(
                      fontSize: 30,
                      height: 1.05,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ch.prettyCategory,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: TvRoyal.textSecondary,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Bouton « Recherche » en bas à droite. Surligné quand la
            // colonne APERÇU a le focus (Droite depuis la liste) ; OK
            // l'active alors.
            _PreviewSearchButton(
              label: _kSearchLabel,
              focused: _pane == _Pane.preview,
              onTap: _openSearch,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Programme EPG en cours + barre de progression.
        if (prog != null) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  prog.title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                prog.timeRangeShort,
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 15,
                  color: TvRoyal.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _EpgProgressBar(program: prog),
        ] else
          Text(
            _kNoProgram,
            style: AppTextStyles.bodyMedium.copyWith(
              color: TvRoyal.textTertiary,
              fontSize: 14,
            ),
          ),
      ],
    );
  }
}

// ============================================================
//  Ligne « catégorie » (colonne de gauche)
// ============================================================

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.count,
    required this.selected,
    required this.paneActive,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool paneActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Surlignage : plein accent quand la colonne est ACTIVE et la ligne
    // sélectionnée ; teinte douce si sélectionnée mais colonne inactive.
    final bool strong = selected && paneActive;
    final Color bg = strong
        ? TvRoyal.accentSurface
        : (selected ? TvRoyal.surfaceHigh : Colors.transparent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: strong ? TvRoyal.accent : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 15,
                    color: strong ? TvRoyal.textPrimary : TvRoyal.textSecondary,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 13,
                  color: TvRoyal.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Ligne « chaîne » : [numéro]  [logo]  [nom]  (+ étoile favori)
// ============================================================

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.number,
    required this.channel,
    required this.selected,
    required this.paneActive,
    required this.isFavorite,
    required this.onTap,
  });

  final int number;
  final Channel channel;
  final bool selected;
  final bool paneActive;
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool strong = selected && paneActive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            // Barre pleine couleur d'accent sur la ligne FOCUSÉE (lisible
            // à 3 m), teinte douce si sélectionnée colonne inactive.
            color: strong
                ? TvRoyal.accentSurface
                : (selected ? TvRoyal.surfaceHigh.withValues(alpha: 0.6) : Colors.transparent),
            border: Border(
              left: BorderSide(
                color: strong ? TvRoyal.accent : Colors.transparent,
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: <Widget>[
              // Numéro de chaîne (colonne alignée, chiffres tabulaires).
              SizedBox(
                width: 44,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 18,
                    color: strong ? TvRoyal.accentGlow : TvRoyal.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Logo
              ChannelLogo(channel: channel, size: ChannelLogoSize.compact),
              const SizedBox(width: 14),
              // Nom
              Expanded(
                child: Text(
                  channel.cleanName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 17,
                    color: strong ? TvRoyal.textPrimary : TvRoyal.textSecondary,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFavorite) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.star_rounded, color: TvRoyal.accentGlow, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Bouton « Recherche » de l'overlay (focusable au D-pad)
// ============================================================

/// Bouton « Recherche » de l'overlay aperçu. Son surlignage est piloté
/// par le prop [focused] (= colonne APERÇU active), pas par le focus
/// Flutter : sur cet écran, c'est le `Focus` racine qui capte toutes les
/// touches de la télécommande pour piloter la navigation custom.
class _PreviewSearchButton extends StatelessWidget {
  const _PreviewSearchButton({
    required this.label,
    required this.focused,
    required this.onTap,
  });

  final String label;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? TvRoyal.accent : TvRoyal.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            boxShadow: focused ? TvRoyal.focusGlow(intensity: 0.7) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.search_rounded,
                size: 22,
                color: focused ? TvRoyal.voidSurface : TvRoyal.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.button.copyWith(
                  fontSize: 16,
                  color: focused ? TvRoyal.voidSurface : TvRoyal.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Barre de progression EPG (position dans le programme en cours)
// ============================================================

class _EpgProgressBar extends StatelessWidget {
  const _EpgProgressBar({required this.program});

  final EpgProgram program;

  @override
  Widget build(BuildContext context) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int span = (program.stopTime - program.startTime).clamp(1, 1 << 62);
    final double progress =
        ((now - program.startTime) / span).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 6,
        backgroundColor: TvRoyal.surfaceHigh,
        valueColor: const AlwaysStoppedAnimation<Color>(TvRoyal.accent),
      ),
    );
  }
}
