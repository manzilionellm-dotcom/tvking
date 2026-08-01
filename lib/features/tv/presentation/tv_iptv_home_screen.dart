// =========================================================
//  tv_iptv_home_screen.dart — Modèle B (design fourni par le client)
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
//    • carte qui grandit et s'entoure d'un halo à l'accent au focus.
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

import '../../../widgets/optimized_image.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../data/iptv_sections.dart';
import 'tv_player_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
    _chanSub =
        PlaylistRepository.instance.channelsStream.listen((_) => _refresh());
    // L'ambiance suit l'heure : à 19 h pile, l'écran bascule tout seul.
    _clock = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() {});
    });
    _favSub = FavoritesRepository.instance.favoritesStream.listen((_) {
      if (mounted && _selected == 'favoris') setState(() {});
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
    });
  }

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

  /// Chaînes de la section choisie. Un seul parcours du bouquet — pas de
  /// pré-calcul de 40 000 entrées à chaque changement de section.
  List<Channel> get _visible {
    final String sel = _selected;
    if (sel == 'favoris') {
      final Set<String> favs = FavoritesRepository.instance.current.toSet();
      return _all.where((Channel c) => favs.contains(c.id)).toList();
    }
    if (sel == 'sports') {
      return _all.where((Channel c) => _matches(c, kSportsKeys)).toList();
    }
    if (sel == 'films') {
      return _all.where((Channel c) => _matches(c, kFilmsKeys)).toList();
    }
    if (sel == 'international') {
      // Tout ce qui n'appartient à aucun des pays listés à gauche.
      final Set<String> shown =
          _countries.map((IptvSection s) => s.id).toSet();
      return _all
          .where((Channel c) => !shown.contains(countryOfCategory(c.category)))
          .toList();
    }
    return _all
        .where((Channel c) => countryOfCategory(c.category) == sel)
        .toList();
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
    final List<Channel> visible = _visible;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: <Widget>[
            _sidebar(),
            Expanded(child: _content(visible)),
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
          const SizedBox(height: 32),
          for (int i = 0; i < _countries.length; i++)
            _SidebarItem(
              section: _countries[i],
              selected: _selected == _countries[i].id,
              accent: _accent,
              autofocus: i == 0,
              onSelect: () => setState(() => _selected = _countries[i].id),
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
              onSelect: () => setState(() => _selected = s.id),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Contenu droit : en-tête + grille ----
  Widget _content(List<Channel> visible) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$_title  ·  ${visible.length}',
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isEvening ? 'Mode soirée' : 'Mode jour',
                  style: TextStyle(color: _accent, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
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
                    onSelect: () => _play(visible, i),
                  ),
                ),
        ),
      ],
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
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
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

/// Carte de chaîne : logo, nom, programme en cours.
class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
    super.key,
    required this.channel,
    required this.accent,
    required this.cardColor,
    required this.onSelect,
  });

  final Channel channel;
  final Color accent;
  final Color cardColor;
  final VoidCallback onSelect;

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
      title =
          (await EpgRepository.instance.currentProgram(widget.channel.id))
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
      ),
    );
  }
}
