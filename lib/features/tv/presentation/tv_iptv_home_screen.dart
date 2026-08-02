// =========================================================
//  tv_iptv_home_screen.dart — Modèle A (accueil principal, design client)
// =========================================================
//  Reprise FIDÈLE de la maquette corrigée par le client :
//    • menu LATÉRAL à gauche (260 px, fond plus sombre) : titre IPTV,
//      les 5 pays, un séparateur, puis Sports / Films / International /
//      Favoris ;
//    • à droite : en-tête (nom de la section + pastille du mode) puis une
//      grille de chaînes en 4 colonnes ;
//    • sous chaque nom de chaîne, le PROGRAMME EN COURS ;
//    • ambiance qui suit l'heure — « Mode soirée » après 19 h, « Mode
//      jour » sinon (fonds et accent différents) ;
//    • carte qui grandit et s'entoure d'un halo à l'accent au focus ;
//    • en haut du menu : RECHERCHER et METTRE À JOUR ;
//    • un cœur en coin de carte — appui LONG sur OK pour l'allumer.
//
//  C'est l'ACCUEIL PRINCIPAL depuis le 2026-08-01 (« je veux que B soit
//  l'app primordiale ») : il s'appelle donc « Modèle A », et l'ancien
//  accueil devient le « Modèle B ».
//
//  ADAPTATIONS pour que ce soit un vrai accueil de TV :
//    • LES 5 PAYS SONT DÉDUITS DU BOUQUET RÉEL (iptv_sections). La
//      maquette les écrivait en dur (France, UK, US, Allemagne, Espagne)
//      — or la source du client est belge : cinq sections vides. On garde
//      sa structure, on remplit avec ce qu'il a vraiment.
//    • vrai focus télécommande (TvFocusBuilder) au lieu d'un Focus
//      décoratif : D-pad, OK, tactile — et OK ouvre le plein écran ;
//    • grille PARESSEUSE : 40 000 chaînes coûtent autant que 12 ;
//    • programme en cours lu dans l'EPG locale (cache 60 s), seulement
//      pour les cartes VISIBLES — jamais 40 000 requêtes ;
//    • logos via OptimizedImage (mémoire et disque bornés) avec repli sur
//      le monogramme doré.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../device/data/device_identity.dart';
import '../../../core/update/update_prompt.dart';
import '../../../widgets/optimized_image.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_sync.dart';
import '../core/tv_focusable.dart';
import '../core/tv_home_template.dart';
import '../core/tv_logo.dart';
import '../data/channel_reliability.dart';
import '../data/iptv_sections.dart';
import 'tv_app.dart' show RestartWidget, showExitDialog;
import 'tv_films_screen.dart';
import 'tv_player_screen.dart';
import 'tv_components.dart';
import 'tv_search_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';
import 'tv_smart_add_screen.dart';

class TvIptvHomeScreen extends StatefulWidget {
  const TvIptvHomeScreen({super.key});

  @override
  State<TvIptvHomeScreen> createState() => _TvIptvHomeScreenState();
}

class _TvIptvHomeScreenState extends State<TvIptvHomeScreen> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<Set<String>>? _favSub;
  Timer? _clock;

  List<Channel> _all = const <Channel>[];
  List<IptvSection> _countries = const <IptvSection>[];
  String _selected = '';

  /// Chaînes de la section courante, DÉJÀ filtrées et triées. Calculé une
  /// seule fois par changement (section, bouquet, favoris) — jamais à
  /// chaque image : sur 40 000 chaînes, trier à chaque rendu ferait
  /// saccader le simple déplacement du focus.
  List<Channel> _visible = const <Channel>[];

  /// Favoris de la portée active — pour le petit cœur en coin de carte.
  Set<String> _favs = <String>{};

  /// Identifiant de l'appareil, montré sur l'écran d'accueil quand aucune
  /// source n'est encore ajoutée : c'est ce code que le client donne à son
  /// revendeur pour se faire activer.
  String _mac = '…';

  /// Y a-t-il au moins UNE source enregistrée ? Ne dit RIEN sur le fait
  /// qu'elle contienne des chaînes — les deux cas mènent à l'accueil,
  /// mais pas avec le même texte ni le même bouton.
  bool _hasSource = false;

  /// Le premier chargement est-il retombé ? Au démarrage, le bouquet met
  /// un instant à arriver du disque : sans ce drapeau, l'écran d'accueil
  /// clignoterait une demi-seconde avant les chaînes, à chaque ouverture.
  /// Passe à vrai dès qu'un événement de chaînes arrive, et de toute
  /// façon au bout de [_kSettleDelay] — un appareil sans aucune source
  /// n'émettra jamais cet événement, il ne faut pas l'attendre pour rien.
  bool _settled = false;
  Timer? _settle;
  static const Duration _kSettleDelay = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _refresh();
    _settle = Timer(_kSettleDelay, () {
      if (mounted) setState(() => _settled = true);
    });
    // Le tri « ce qui marche vraiment chez toi d'abord » lit la fiabilité
    // apprise (n°38). Elle arrive du disque : on retrie à son arrivée.
    unawaited(ChannelReliability.instance.load().then((_) {
      if (mounted) setState(_recompute);
    }));
    _chanSub = PlaylistRepository.instance.channelsStream.listen((_) {
      _settled = true; // le dépôt a parlé : on sait à quoi s'en tenir
      _refresh();
    });
    // L'ambiance suit l'heure : à 19 h pile, l'écran bascule tout seul.
    _clock = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() {});
    });
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    }).catchError((_) {});
    _favs = FavoritesRepository.instance.current.toSet();
    _favSub =
        FavoritesRepository.instance.favoritesStream.listen((Set<String> f) {
      if (!mounted) return;
      setState(() {
        _favs = f.toSet();
        // Dans la section Favoris, retirer un cœur retire la carte.
        if (_selected == 'favoris') _recompute();
      });
    });
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _favSub?.cancel();
    _clock?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  void _refresh() {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    final Map<String, int> counts = <String, int>{};
    for (final Channel c in all) {
      counts[c.category] = (counts[c.category] ?? 0) + 1;
    }
    final List<IptvSection> countries = topCountrySections(counts);
    if (!mounted) return;
    final bool hasSource =
        PlaylistRepository.instance.currentPlaylists.isNotEmpty;
    setState(() {
      _all = all;
      _hasSource = hasSource;
      _countries = countries;
      if (_selected.isEmpty) {
        _selected = countries.isNotEmpty ? countries.first.id : 'international';
      }
      _recompute();
    });
  }

  /// Changement de section : on recalcule ICI, pas dans build().
  void _select(String id) {
    if (id == _selected) return;
    setState(() {
      _selected = id;
      _recompute();
    });
  }

  /// Le modèle proposé par la pastille du haut. Cet écran EST le Modèle A
  /// (`iptv`) — la pastille propose donc « Modèle B ».
  static final TvHomeTemplate _nextTemplate =
      otherTemplate(TvHomeTemplate.iptv);

  // ---- Ambiance selon l'heure (spécification client) ----
  bool get _isEvening {
    final int h = DateTime.now().hour;
    return h >= 19 || h < 6;
  }

  Color get _bg =>
      _isEvening ? const Color(0xFF0B0F14) : const Color(0xFF0F1419);
  Color get _card =>
      _isEvening ? const Color(0xFF151A21) : const Color(0xFF1A2028);
  Color get _accent =>
      _isEvening ? const Color(0xFF4ECDC4) : const Color(0xFF00D4FF);

  /// Recalcule la section courante : UN seul parcours du bouquet, puis le
  /// tri voulu par le client (Sport → Info → le reste, puis la qualité).
  void _recompute() {
    final String sel = _selected;
    List<Channel> list;
    if (sel == 'favoris') {
      final Set<String> favs = FavoritesRepository.instance.current.toSet();
      list = _all.where((Channel c) => favs.contains(c.id)).toList();
    } else if (sel == 'sports') {
      // « Sports » = le sport de TOUS les pays du menu réunis.
      list = _all
          .where((Channel c) =>
              c.genre == ChannelGenre.sports || _matches(c, kSportsKeys))
          .toList();
    } else if (sel == 'international') {
      // Tout ce qui n'appartient à aucun des pays listés à gauche.
      final Set<String> shown = _countries.map((IptvSection s) => s.id).toSet();
      list = _all
          .where((Channel c) => !shown.contains(countryOfCategory(c.category)))
          .toList();
    } else {
      list = _all
          .where((Channel c) => countryOfCategory(c.category) == sel)
          .toList();
    }
    // Ordre demandé par le client : Sport → Info → le reste ; à genre égal,
    // ce qui s'ouvre le mieux CHEZ LUI passe devant (fiabilité n°38).
    sortIptvChannels(list, scoreOf: ChannelReliability.instance.scoreOf);
    _visible = list;
  }

  static bool _matches(Channel c, List<String> keys) {
    final String up = c.category.toUpperCase();
    for (final String k in keys) {
      if (up.contains(k)) return true;
    }
    return false;
  }

  String get _title {
    for (final IptvSection s in _countries) {
      if (s.id == _selected) return s.label;
    }
    for (final IptvSection s in kIptvFixedSections) {
      if (s.id == _selected) return s.label;
    }
    return 'Chaînes';
  }

  void _play(List<Channel> list, int index) {
    if (list.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: TvPlayerScreen(channels: list, startIndex: index),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // RETOUR / EXIT (signalé par le client : « quand on retourne pour faire
    // Exit, ça marche pas »). Le PopScope racine de tv_app laisse la main à
    // l'accueil ; cet accueil-ci ne la prenait pas, donc le bouton Retour ne
    // faisait RIEN. Il ouvre maintenant la boîte « Quitter l'application ?
    // Oui / Non », comme sur l'autre modèle.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop || _exitAsked) return;
        _exitAsked = true;
        final String? action = await showExitDialog(context);
        _exitAsked = false;
        if (!mounted) return;
        if (action == 'restart') {
          RestartWidget.restart(context);
        } else if (action == 'quit') {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          // ZÉRO CHAÎNE = ÉCRAN D'ACCUEIL, quoi qu'il arrive.
          //
          // Le critère n'est PAS « a-t-il une source enregistrée » — c'est
          // l'erreur que le client a dû signaler deux fois. Une source
          // peut être enregistrée et ne rien contenir (abonnement vidé,
          // expiré, jamais chargé) : il retombait alors sur un menu vide
          // et « Aucune chaîne dans cette section ». Un cul-de-sac.
          //
          // Le critère, c'est LE BOUQUET. S'il est vide, on accueille —
          // et le texte s'adapte selon qu'une source existe déjà ou non.
          child: _all.isNotEmpty
              ? Row(
                  children: <Widget>[
                    _sidebar(),
                    Expanded(child: _content(_visible)),
                  ],
                )
              // Tant que le premier chargement n'est pas retombé et qu'une
              // source existe, on patiente : sinon l'accueil clignoterait
              // une demi-seconde à chaque ouverture, avant les chaînes.
              : (!_settled && _hasSource)
                  ? _loading()
                  : _welcome(),
        ),
      ),
    );
  }

  /// Garde-fou : deux appuis rapides sur Retour ne doivent pas empiler deux
  /// boîtes de dialogue l'une sur l'autre.
  bool _exitAsked = false;

  /// Vrai pendant le rechargement lancé depuis l'écran d'accueil.
  bool _reloading = false;

  /// « Recharger ma source » — le MÊME moteur que le bouton du téléphone
  /// (`SourceSync`) : on redemande au serveur la source assignée à cette
  /// MAC, puis on re-télécharge le bouquet. C'est exactement le geste
  /// qu'attend quelqu'un dont la source est enregistrée mais vide.
  Future<void> _reloadSource() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    final SyncReport r = await SourceSync.run();
    if (!mounted) return;
    setState(() => _reloading = false);
    // Si des chaînes sont arrivées, `channelsStream` a déjà rebasculé
    // l'écran sur l'accueil rempli : inutile d'annoncer quoi que ce soit.
    if (r.channelsAfter > 0) return;
    final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF1A2028),
        content: Text(
          syncResultText(r),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  /// Écran d'attente du tout premier chargement. Volontairement nu : il
  /// ne dure qu'une fraction de seconde, et une box qui affiche un gros
  /// décor pour le remplacer aussitôt donne une impression de clignotement.
  Widget _loading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TvLogo(width: 170),
          const SizedBox(height: 26),
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _accent),
          ),
          const SizedBox(height: 18),
          Text(
            'Chargement de tes chaînes…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Écran d'ACCUEIL : le bouquet est VIDE ----
  //  Signalé par le client : « le A ne montre rien à quelqu'un qui n'a pas
  //  le lien ». Un menu vide et un « aucune chaîne » sont un cul-de-sac.
  //
  //  DEUX SITUATIONS, deux textes, deux boutons principaux :
  //    • aucune source enregistrée → « Ajouter ma source » ;
  //    • une source enregistrée mais VIDE (abonnement vidé, expiré, ou
  //      jamais chargé) → « Recharger ma source ». Ce deuxième cas est
  //      celui que le client a rencontré : proposer « Ajouter » à
  //      quelqu'un qui a déjà sa source ne l'aide pas, il faut lui
  //      proposer de la relancer.
  //
  //  Dans les deux cas : son identifiant d'appareil, et le QR pour
  //  joindre son revendeur.
  Widget _welcome() {
    final bool emptySource = _hasSource;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // Une box 720p ne laisse qu'environ 640 px utiles en hauteur, et
        // certaines dalles descendent plus bas. Rien ici n'a de taille
        // fixe : le QR se met à l'échelle de la place restante, la
        // colonne de gauche défile en dernier recours, et les deux
        // boutons secondaires passent à la ligne plutôt que de déborder.
        final bool tight = c.maxHeight < 620;
        final double qr = c.maxHeight.clamp(320.0, 900.0) * 0.26;
        final double pad = tight ? 28 : 48;
        return Padding(
          padding:
              EdgeInsets.fromLTRB(pad, tight ? 20 : 32, pad, tight ? 20 : 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TvLogo(width: tight ? 150 : 190),
                      SizedBox(height: tight ? 14 : 22),
                      Text(
                        emptySource ? 'Aucune chaîne' : 'Bienvenue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: tight ? 30 : 38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        emptySource
                            ? 'Ta source est bien enregistrée, mais elle ne '
                                'contient aucune chaîne pour l\'instant. '
                                'Recharge-la, ou demande à ton fournisseur de '
                                'la remplir.'
                            : 'Ajoute la source que ton fournisseur t\'a '
                                'donnée — un lien M3U ou un compte Xtream. '
                                'Elle t\'appartient : l\'application ne '
                                'fournit aucune chaîne.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: tight ? 14 : 16,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: tight ? 18 : 26),
                      // Le bouton PRINCIPAL, focus par défaut : un appui
                      // sur OK et il est dans le bon geste, sans chercher.
                      // « Recharger » quand la source existe déjà — lui
                      // proposer « Ajouter » ne l'aiderait pas.
                      _WelcomeButton(
                        icon: emptySource
                            ? Icons.sync_rounded
                            : Icons.add_link_rounded,
                        label: emptySource
                            ? 'Recharger ma source'
                            : 'Ajouter ma source',
                        accent: _accent,
                        primary: true,
                        autofocus: true,
                        onSelect: () {
                          if (emptySource) {
                            unawaited(_reloadSource());
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const TvShell(child: TvSmartAddScreen()),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _WelcomeButton(
                            icon: Icons.settings_rounded,
                            label: 'Réglages',
                            accent: _accent,
                            onSelect: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TvSettingsScreen(),
                              ),
                            ),
                          ),
                          _WelcomeButton(
                            icon: Icons.system_update_rounded,
                            label: 'Mettre à jour',
                            accent: _accent,
                            onSelect: () =>
                                unawaited(checkForUpdatesInteractive(context)),
                          ),
                        ],
                      ),
                      SizedBox(height: tight ? 18 : 26),
                      // L'IDENTIFIANT DE L'APPAREIL : c'est ce code que le
                      // client dicte à son revendeur pour se faire activer.
                      // Il doit être lisible à trois mètres.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'Identifiant de cet appareil',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _mac,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _accent,
                                fontSize: tight ? 20 : 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: tight ? 24 : 40),
              // ----- QR : scanner pour écrire au revendeur, code inclus ---
              TvWhatsAppQr(mac: _mac, size: qr),
            ],
          ),
        );
      },
    );
  }

  // ---- Menu latéral gauche ----
  Widget _sidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF0A0E13),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const SizedBox(height: 40),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'IPTV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ----- RECHERCHE (demande client) -----
          // Le champ de saisie de sa maquette suppose un clavier ; sur une
          // télécommande, c'est l'écran de recherche de l'app qui fait le
          // travail : clavier à l'écran au D-pad, dernières recherches,
          // et résultats sur les CHAÎNES, les FILMS et les SÉRIES.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MenuActionButton(
              icon: Icons.search_rounded,
              label: 'Rechercher…',
              accent: _accent,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TvSearchScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ----- LE BOUTON MAGIQUE (demande client) -----
          // Un seul OK : l'app va chercher la dernière version en ligne, la
          // télécharge avec une barre de progression et lance l'installation
          // PAR-DESSUS (Android remplace l'app sans rien effacer — sources,
          // favoris et réglages restent). Si tout est déjà à jour, elle le
          // dit et ne touche à rien.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MenuActionButton(
              icon: Icons.system_update_rounded,
              label: 'Mettre à jour',
              accent: _accent,
              onSelect: () => unawaited(checkForUpdatesInteractive(context)),
            ),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < _countries.length; i++)
            _SidebarItem(
              section: _countries[i],
              selected: _selected == _countries[i].id,
              accent: _accent,
              autofocus: i == 0,
              onSelect: () => _select(_countries[i].id),
            ),
          const SizedBox(height: 12),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 8),
          for (final IptvSection s in kIptvFixedSections)
            _SidebarItem(
              section: s,
              selected: _selected == s.id,
              accent: _accent,
              autofocus: _countries.isEmpty && s.id == 'sports',
              onSelect: () => _select(s.id),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Contenu droit : en-tête + grille (ou le CINÉMA) ----
  Widget _content(List<Channel> visible) {
    // FILMS = le vrai cinéma de l'app (catalogue VOD, affiche vedette,
    // rangées, fiche détail, reprise de lecture) — pas une grille de
    // chaînes. Le menu latéral reste à gauche : on ne change que le
    // panneau de droite.
    final bool cinema = _selected == 'films';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  cinema ? 'Cinéma' : '$_title  ·  ${visible.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // ----- LES OPTIONS QUI MANQUAIENT (demande client) -----
              // Un petit mot en haut, rien de plus : le nom de l'AUTRE
              // modèle (bascule immédiate) et l'accès aux Réglages.
              //
              // FittedBox : sur un écran étroit (box qui rapporte une
              // résolution logique riquiqui), le groupe RÉTRÉCIT au lieu de
              // déborder. Plus jamais d'en-tête « tout mélangé ».
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Cet écran EST le Modèle B : la pastille propose donc
                      // toujours l'autre (« Modèle A »), sans dépendre de
                      // l'état du dépôt.
                      _MiniChip(
                        icon: Icons.swap_horiz_rounded,
                        label: _nextTemplate.label,
                        accent: _accent,
                        onSelect: () => unawaited(
                          TvHomeTemplateRepository.instance
                              .setTemplate(_nextTemplate),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MiniChip(
                        icon: Icons.settings_rounded,
                        label: 'Réglages',
                        accent: _accent,
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TvSettingsScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isEvening ? 'Mode soirée' : 'Mode jour',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(color: _accent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (cinema)
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 20, right: 20),
              child: TvFilmsScreen(),
            ),
          )
        else
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      'Aucune chaîne dans cette section.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.15,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                    ),
                    // PARESSEUSE : seules les cartes visibles sont
                    // construites — 40 000 chaînes coûtent autant que 12.
                    itemCount: visible.length,
                    itemBuilder: (BuildContext _, int i) => _ChannelCard(
                      key: ValueKey<String>(visible[i].id),
                      channel: visible[i],
                      accent: _accent,
                      cardColor: _card,
                      favorite: _favs.contains(visible[i].id),
                      onSelect: () => _play(visible, i),
                      onToggleFavorite: () => unawaited(
                        FavoritesRepository.instance.toggle(visible[i].id),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Gros bouton d'action en haut du menu latéral (Rechercher, Mettre à
/// jour) — la forme voulue par le client : bien visible, teinté à l'accent,
/// et pilotable à la télécommande.
class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: focused ? 0.24 : 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: focused ? 1 : 0.3),
            width: focused ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.9),
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton de l'écran d'accueil « aucune source ». `primary` = le bouton
/// plein, celui vers lequel on veut que l'œil et le focus aillent.
class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: primary ? TvFocusScale.medium : TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = primary
            ? const Color(0xFF06231F)
            : (focused ? accent : Colors.white.withValues(alpha: 0.85));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: primary ? 30 : 20,
            vertical: primary ? 18 : 13,
          ),
          decoration: BoxDecoration(
            color: primary
                ? accent
                : (focused ? accent.withValues(alpha: 0.18) : null),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? accent : accent.withValues(alpha: 0.3),
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 22,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: primary ? 24 : 19),
              const SizedBox(width: 10),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: fg,
                  fontSize: primary ? 19 : 15,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Petite pastille d'option en haut à droite (bascule de modèle, Réglages).
/// Volontairement DISCRÈTE : le client veut « juste un petit mot en haut »,
/// pas un bandeau qui mange la place du contenu.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: focused ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: focused ? accent : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: focused ? accent : Colors.white.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: focused ? accent : Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entrée du menu latéral — focusable à la télécommande.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.accent,
    required this.onSelect,
    this.autofocus = false,
  });

  final IptvSection section;
  final bool selected;
  final Color accent;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : (focused ? Colors.white.withValues(alpha: 0.06) : null),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? accent : (selected ? accent : Colors.transparent),
            width: 1.5,
          ),
        ),
        child: Row(
          children: <Widget>[
            Text(section.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected || focused
                      ? accent
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (section.count > 0)
              Text(
                '${section.count}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte de chaîne : logo, nom, programme en cours, cœur des favoris.
class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
    super.key,
    required this.channel,
    required this.accent,
    required this.cardColor,
    required this.favorite,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final Color accent;
  final Color cardColor;
  final bool favorite;
  final VoidCallback onSelect;
  final VoidCallback onToggleFavorite;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  String? _program;

  @override
  void initState() {
    super.initState();
    // UNE seule lecture EPG par carte VISIBLE (cache mémoire de 60 s côté
    // dépôt) — la grille étant paresseuse, on ne demande jamais le
    // programme des 40 000 chaînes.
    unawaited(_loadProgram());
  }

  Future<void> _loadProgram() async {
    String? title;
    try {
      title = (await EpgRepository.instance.currentProgram(widget.channel.id))
          ?.title;
    } catch (_) {
      title = null; // EPG absente → la ligne ne s'affiche pas
    }
    if (mounted && title != _program) setState(() => _program = title);
  }

  @override
  Widget build(BuildContext context) {
    final Channel c = widget.channel;
    final String? logo = c.logoUrl;
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: widget.onSelect,
      // APPUI LONG sur OK = ajouter/retirer des favoris. C'est le geste
      // déjà en place partout ailleurs dans l'app : le cœur de sa maquette
      // se touche au doigt, une télécommande n'a pas de doigt.
      onLongPress: () {
        widget.onToggleFavorite();
        HapticFeedback.selectionClick();
      },
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: widget.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused ? widget.accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Stack(
          children: <Widget>[
            // Cœur en coin, comme dans sa maquette : discret quand la
            // chaîne n'est pas en favori, rouge quand elle l'est.
            if (widget.favorite)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.favorite, color: Colors.redAccent, size: 18),
              )
            else if (focused)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.favorite_border,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 18,
                ),
              ),
            _cardBody(c, logo),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(Channel c, String? logo) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 64,
            height: 64,
            child: (logo == null || logo.isEmpty)
                ? TvChannelLogo(
                    logoUrl: null,
                    label: c.name,
                    size: 64,
                    radius: 10,
                  )
                : OptimizedImage(
                    imageUrl: logo,
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.circular(10),
                    fallback: TvChannelLogo(
                      logoUrl: null,
                      label: c.name,
                      size: 64,
                      radius: 10,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              c.cleanName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if ((_program ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _program!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
