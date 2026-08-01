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

import '../../../core/update/update_prompt.dart';
import '../../../widgets/optimized_image.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_home_template.dart';
import '../core/tv_logo.dart';
import '../data/channel_reliability.dart';
import '../data/iptv_sections.dart';
import 'tv_films_screen.dart';
import 'tv_player_screen.dart';
import 'tv_search_screen.dart';
import 'tv_settings_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
    // Le tri « ce qui marche vraiment chez toi d'abord » lit la fiabilité
    // apprise (n°38). Elle arrive du disque : on retrie à son arrivée.
    unawaited(ChannelReliability.instance.load().then((_) {
      if (mounted) setState(_recompute);
    }));
    _chanSub =
        PlaylistRepository.instance.channelsStream.listen((_) => _refresh());
    // L'ambiance suit l'heure : à 19 h pile, l'écran bascule tout seul.
    _clock = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() {});
    });
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
    setState(() {
      _all = all;
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
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: <Widget>[
            _sidebar(),
            Expanded(child: _content(_visible)),
          ],
        ),
      ),
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
