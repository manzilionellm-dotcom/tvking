// =========================================================
//  simple_home_screen.dart — Accueil "simple pour tous"
// =========================================================
//  Navigation en 2 niveaux, pensée pour être évidente (même pour un
//  enfant ou un senior) :
//    1. PAYS  — grille de drapeaux (détectés automatiquement depuis
//       les chaînes via channel.country).
//    2. CATÉGORIES — dans un pays : Récemment regardé, Favoris, puis
//       Sport / Divertissement / Info / Enfants en tuiles colorées.
//       La zone Cinéma & Séries (+ Adulte) est VERROUILLÉE par
//       empreinte/Face ID ou code PIN (cf. CinemaLock).
//
//  Données 100% réelles : PlaylistRepository (chaînes), Favorites,
//  RecentlyWatched, genre/pays calculés sur Channel.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/favorites_screen.dart';
import '../../channels/presentation/search_screen.dart';
import '../../channels/presentation/widgets/empty_state.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../player/presentation/play_channel.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../country_home/data/channel_health_repository.dart';
import '../../country_home/data/country_history_repository.dart';
import '../../country_home/data/featured_repository.dart';
import '../../country_home/data/popularity_repository.dart';
import '../../country_home/data/text_scale_repository.dart';
import '../../country_home/presentation/country_home_view.dart';
import '../data/home_layout_repository.dart';
import 'widgets/announcement_banner.dart';
import 'widgets/media_grid_view.dart';

/// Les 4 écosystèmes du haut, STRICTEMENT séparés (jamais mélangés) :
/// LIVE TV (chaînes), FILMS (VOD), SÉRIES (épisodes), PPV (événements).
enum _Section { liveTv, movies, series, ppv }

// --- Règles de classification (séparation stricte) ---
bool _isMovie(Channel c) => c.genre == ChannelGenre.movies;
bool _isSeries(Channel c) => c.genre == ChannelGenre.series;
bool _isAdult(Channel c) => c.genre == ChannelGenre.adult;

/// PPV / événements : détecté par mot-clé (pas de genre dédié dans les
/// playlists). Conservateur pour éviter les faux positifs.
bool _isPpv(Channel c) {
  final String s = '${c.name} ${c.category}'.toLowerCase();
  return s.contains('ppv') ||
      s.contains('ufc') ||
      s.contains('wwe') ||
      s.contains('wrestl') ||
      s.contains('boxing');
}

/// LIVE TV = tout ce qui n'est NI film, NI série, NI adulte, NI PPV.
/// (Les "chaînes cinéma" live restent en LIVE TV — ce sont des chaînes.)
bool _isLiveTv(Channel c) =>
    !_isMovie(c) && !_isSeries(c) && !_isAdult(c) && !_isPpv(c);

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  /// Code pays sélectionné (`null` = on est sur la grille des pays).
  /// Écosystème courant (haut de l'écran). Défaut : LIVE TV.
  /// (Nommé `_activeSection` pour ne pas entrer en collision avec
  /// l'ancienne méthode `_section(...)` encore présente plus bas.)
  _Section _activeSection = _Section.liveTv;

  String? _countryCode;
  String _countryFlag = '';
  String _countryName = '';

  @override
  void initState() {
    super.initState();
    FavoritesRepository.instance.initialize();
    RecentlyWatchedRepository.instance.initialize();
    // Accueil dynamique (Centre de contrôle) : charge la disposition
    // pilotée à distance (cache immédiat puis rafraîchissement réseau).
    HomeLayoutRepository.instance.initialize();
    // Accueil "Maison Noir" : score de popularité + réglage texte.
    PopularityRepository.instance.initialize();
    TextScaleRepository.instance.initialize();
    // "Vos pays" (récents) pour l'écran de choix de pays.
    CountryHistoryRepository.instance.initialize();
    // Santé des chaînes : charge le cache (la sonde démarre au 1er
    // affichage des chaînes, cf. build → _healthKicked).
    ChannelHealthRepository.instance.initialize();
    // "Favori du jour" piloté depuis le panel.
    FeaturedRepository.instance.initialize();
  }

  // Sonde de santé déclenchée une seule fois par session, dès que les
  // chaînes sont chargées (en arrière-plan, ne bloque pas l'UI).
  bool _healthKicked = false;

  /// Ouvre un pays + le mémorise dans "Vos pays" (récents).
  void _openCountry(_Country c) {
    CountryHistoryRepository.instance.record(c.code);
    setState(() {
      _countryCode = c.code;
      _countryFlag = c.flag;
      _countryName = c.name;
    });
  }

  /// Formate un nombre avec séparateur de milliers FR (12 000).
  String _fmtThousands(int n) {
    final String s = n.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Fond dégradé subtil (même profondeur "cinéma" que la TV), en
      // gardant l'identité rouge ember du mobile.
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
        child: StreamBuilder<List<Channel>>(
          stream: PlaylistRepository.instance.channelsStream,
          initialData: PlaylistRepository.instance.currentChannels,
          builder: (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
            final List<Channel> channels = snap.data ?? const <Channel>[];
            // Au 1er chargement des chaînes : lance la sonde de santé en
            // arrière-plan (top popularité, bornée → pas de risque de ban).
            if (!_healthKicked && channels.isNotEmpty) {
              _healthKicked = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => ChannelHealthRepository.instance.probeTop(channels),
              );
            }
            return Column(
              children: <Widget>[
                _buildHeader(channels.isNotEmpty),
                // Bandeau « message à tous » (annonce admin). Auto-géré :
                // ne prend aucune place s'il n'y a rien à montrer.
                const AnnouncementBanner(),
                // Navigation principale : les 4 écosystèmes (jamais mélangés).
                if (channels.isNotEmpty) _buildSectionTabs(),
                Expanded(
                  child: channels.isEmpty
                      ? EmptyStateView(
                          onAddPlaylist: () => showSourceChoiceSheet(context),
                        )
                      : _buildSectionBody(channels),
                ),
                _buildBottomBar(),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  // ----- En-tête -----
  Widget _buildHeader(bool hasChannels) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: <Widget>[
          if (_countryCode != null)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _countryCode = null),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: BrandLogo.compact(),
            ),
          Expanded(
            child: Text(
              switch (_activeSection) {
                _Section.liveTv => _countryCode == null
                    ? context.l10n.simpleChooseCountry
                    : '$_countryFlag  $_countryName',
                _Section.movies => 'Films',
                _Section.series => 'Séries',
                _Section.ppv => 'PPV / Événements',
              },
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: context.l10n.simpleMyAccount,
            icon: const Icon(Icons.person_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Barre des 4 écosystèmes (séparation stricte) -----
  Widget _buildSectionTabs() {
    const List<(_Section, String, IconData)> items =
        <(_Section, String, IconData)>[
      (_Section.liveTv, 'LIVE TV', Icons.live_tv_rounded),
      (_Section.movies, 'FILMS', Icons.movie_rounded),
      (_Section.series, 'SÉRIES', Icons.video_library_rounded),
      (_Section.ppv, 'PPV', Icons.sports_mma_rounded),
    ];
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: <Widget>[
          for (final (_Section s, String label, IconData icon) in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _sectionTab(s, label, icon),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTab(_Section s, String label, IconData icon) {
    final bool active = _activeSection == s;
    return Material(
      color: active ? AppColors.black7Red : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _activeSection = s;
          _countryCode = null; // on revient à la racine de l'écosystème
        }),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon,
                size: 16,
                color: active ? Colors.white : AppColors.textTertiary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.maisonLabel.copyWith(
                    fontSize: 11,
                    color: active ? Colors.white : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Corps selon l'écosystème courant. Séparation stricte : chaque section
  // ne reçoit QUE les contenus de son type.
  Widget _buildSectionBody(List<Channel> channels) {
    // `return switch` = exhaustif et retour garanti par le compilateur.
    return switch (_activeSection) {
      _Section.liveTv => _buildLiveBody(channels),
      _Section.movies => MediaGridView(
          channels: channels.where(_isMovie).toList(),
          emptyLabel: 'Aucun film dans ta playlist.',
        ),
      _Section.series => MediaGridView(
          channels: channels.where(_isSeries).toList(),
          emptyLabel: 'Aucune série dans ta playlist.',
        ),
      _Section.ppv => MediaGridView(
          channels: channels.where(_isPpv).toList(),
          emptyLabel: 'Aucun événement PPV pour le moment.',
        ),
    };
  }

  // LIVE TV : navigation par pays, filtrée aux chaînes live uniquement.
  Widget _buildLiveBody(List<Channel> channels) {
    final List<Channel> live = channels.where(_isLiveTv).toList();
    return _countryCode == null
        ? _buildCountryGrid(live)
        : _buildCountryDetail(live);
  }

  // ----- Niveau 1 : grille des pays -----
  Widget _buildCountryGrid(List<Channel> channels) {
    // Regroupe par pays (code). Sans pays détecté → International 🌍.
    final Map<String, _Country> byCode = <String, _Country>{};
    for (final Channel c in channels) {
      final CountryInfo? co = c.country;
      final String code = co?.code ?? 'intl';
      final _Country entry = byCode.putIfAbsent(
        code,
        () => _Country(
          code: code,
          name: co?.name ?? 'International',
          flag: co?.flag ?? '🌍',
        ),
      );
      entry.count++;
    }
    final List<_Country> countries = byCode.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // "Vos pays" : récents persistés (CountryHistoryRepository), filtrés
    // à ceux encore présents dans la playlist actuelle.
    return ListenableBuilder(
      listenable: CountryHistoryRepository.instance,
      builder: (BuildContext context, _) {
        final List<String> recentCodes =
            CountryHistoryRepository.instance.getRecentCountries();
        final List<_Country> recent = <_Country>[
          for (final String code in recentCodes)
            if (byCode[code] != null) byCode[code]!,
        ];
        return ColoredBox(
          color: AppColors.maisonBg,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              if (recent.isNotEmpty) ...<Widget>[
                _countrySectionTitle('Vos pays'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, int i) => SizedBox(
                        width: 108,
                        child: _countryCard(recent[i]),
                      ),
                    ),
                  ),
                ),
              ],
              _countrySectionTitle('Tous les pays'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int i) =>
                        _countryCard(countries[i], popular: i < 3),
                    childCount: countries.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _countrySectionTitle(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Text(
            text,
            style: AppTextStyles.maisonSection.copyWith(fontSize: 19),
          ),
        ),
      );

  // Carte pays (drapeau + nom + "X chaînes"), badge POPULAIRE (rouge) sur
  // les plus fournies. Charte Black7.
  Widget _countryCard(_Country c, {bool popular = false}) {
    return Material(
      color: AppColors.maisonSurface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCountry(c),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(c.flag, style: const TextStyle(fontSize: 42)),
                  const SizedBox(height: 6),
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.maisonChannelName.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtThousands(c.count)} chaînes',
                    style: AppTextStyles.maisonProgram.copyWith(
                        fontSize: 11.5, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            if (popular)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.black7Red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'POPULAIRE',
                    style: AppTextStyles.maisonLabel.copyWith(
                        color: AppColors.maisonInk, fontSize: 8.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ----- Niveau 2 : détail d'un pays (accueil "Maison Noir" refondu) -----
  Widget _buildCountryDetail(List<Channel> allChannels) {
    // Chaînes LIVE de ce pays (allChannels est déjà filtré "live" par
    // _buildSectionBody → ni films, ni séries, ni adulte, ni PPV).
    final List<Channel> channels = allChannels
        .where((Channel c) => (c.country?.code ?? 'intl') == _countryCode)
        .toList();
    // Accueil curé LIVE TV (HERO, Populaires, Reprendre, sections). Plus
    // aucune zone verrouillée : Films/Séries ont désormais leurs propres
    // écosystèmes (onglets FILMS / SÉRIES). Le verrou Cinéma est supprimé.
    return CountryHomeView(channels: channels);
  }

  // (Zone Cinéma VERROUILLÉE supprimée — Films/Séries ont leurs propres
  //  écosystèmes, plus aucun code/PIN/biométrie côté cinéma.)

  // ----- Une section (rangée horizontale de tuiles) -----
  //  En-tête « joyeux » : gros emoji ANIMÉ (balancement + pulsation, style
  //  Duolingo) dans une pastille teintée à la couleur de la catégorie, +
  //  titre. Puis une rangée de cartes de chaînes compactes et modernes.
  Widget _section(
      String emoji, String title, Color accent, List<Channel> items,
      Set<String> favs,
      {String ribbon = '', bool featured = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Row(
              children: <Widget>[
                // Pastille emoji géant + animé.
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _WiggleEmoji(emoji, size: 26),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineMedium.copyWith(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                // Ruban piloté à distance (NOUVEAU / EN DIRECT / …).
                if (ribbon.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  _RibbonBadge(ribbon),
                ],
                // Étoile "mis en vedette".
                if (featured) ...<Widget>[
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded,
                      color: AppColors.warning, size: 18),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length > 40 ? 40 : items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int i) => _ChannelTile(
                channel: items[i],
                accent: accent,
                isFav: favs.contains(items[i].id),
                onTap: () => playChannel(context, items[i], zapPlaylist: items),
                onFav: () =>
                    FavoritesRepository.instance.toggle(items[i].id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Barre du bas -----
  //  4 destinations claires avec libellés et état actif. "Accueil" est
  //  l'onglet courant (mis en avant ember). Avant, l'icône cœur ouvrait
  //  par erreur l'ajout de source — corrigé : Favoris ouvre les favoris,
  //  et un bouton "Ajouter" dédié gère l'ajout de playlist.
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.35),
        border: const Border(top: BorderSide(color: AppColors.surface)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: context.l10n.navHome,
            active: true,
            onTap: () => setState(() => _countryCode = null),
          ),
          _BottomNavItem(
            icon: Icons.favorite_rounded,
            label: context.l10n.navFavorites,
            active: false,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
            ),
          ),
          // ----- Bouton RECHERCHE IA, au centre et mis en avant -----
          //  Ouvre SearchScreen → champ « Demander à l'IA » (langage
          //  naturel). Accentué (ember) pour en faire l'action vedette.
          _BottomNavItem(
            icon: Icons.auto_awesome_rounded,
            label: context.l10n.navAi,
            active: false,
            accent: true,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          _BottomNavItem(
            icon: Icons.add_circle_outline_rounded,
            label: context.l10n.buttonAdd,
            active: false,
            onTap: () => showSourceChoiceSheet(context),
          ),
        ],
      ),
    );
  }
}

/// Élément de la barre de navigation du bas (mobile) — icône + libellé,
/// teinté ember quand actif, estompé sinon.
class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Onglet « vedette » (la recherche IA) : toujours teinté ember, avec
  /// l'icône posée sur une pastille accent pour ressortir au centre.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    // Couleur du texte/icône : ember si actif OU accentué, estompé sinon.
    final Color color =
        (active || accent) ? AppColors.accent : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // L'onglet IA met son icône dans une pastille ember pour
            // accrocher l'œil au centre de la barre.
            if (accent)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: color, size: 26),
              )
            else
              Icon(icon, color: color, size: 26),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: accent ? FontWeight.w800 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Country {
  _Country({required this.code, required this.name, required this.flag});
  final String code;
  final String name;
  final String flag;
  int count = 0;
}

/// Petit ruban coloré affiché à côté du titre d'une section (piloté à
/// distance par le Centre de contrôle : NOUVEAU, EN DIRECT, UFC, …).
class _RibbonBadge extends StatelessWidget {
  const _RibbonBadge(this.label);
  final String label;

  Color get _color {
    switch (label) {
      case 'NOUVEAU':
        return AppColors.success;
      case 'EXCLUSIF':
      case 'VIP':
        return AppColors.warning;
      case 'EN DIRECT':
      case 'COUPE DU MONDE':
      case 'EURO 2028':
      case 'UFC':
      case 'CHAMPIONS LEAGUE':
        return AppColors.live;
      case 'POPULAIRE':
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: c,
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.accent,
    required this.isFav,
    required this.onTap,
    required this.onFav,
  });

  final Channel channel;
  final Color accent;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    // Carte COMPACTE et MODERNE : plus petite (80 px), coins très
    // arrondis, liseré accent discret (alpha) + ombre douce colorée, et
    // le logo posé sur une vignette arrondie claire (look « app store »).
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent.withValues(alpha: 0.55),
            width: 1.3,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Vignette logo arrondie.
                Container(
                  width: 46,
                  height: 36,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: channel.hasLogo
                      ? Image.network(
                          channel.logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Icon(channel.genre.icon, color: accent, size: 22),
                        )
                      : Icon(channel.genre.icon, color: accent, size: 24),
                ),
                const SizedBox(height: 7),
                Text(
                  channel.cleanName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Positioned(
              top: -2,
              right: -2,
              child: GestureDetector(
                onTap: onFav,
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: isFav ? AppColors.live : AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Emoji « vivant » : balancement (rotation) + légère pulsation en boucle,
/// style mascotte Duolingo — ça donne envie de sourire même de mauvaise
/// humeur. Désynchronisé d'un emoji à l'autre (durée/phase dérivées de
/// l'emoji) pour éviter l'effet « tout bouge en même temps ». Respecte le
/// réglage système « réduire les animations ».
class _WiggleEmoji extends StatefulWidget {
  const _WiggleEmoji(this.emoji, {this.size = 26});

  final String emoji;
  final double size;

  @override
  State<_WiggleEmoji> createState() => _WiggleEmojiState();
}

class _WiggleEmojiState extends State<_WiggleEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final int seed = widget.emoji.hashCode.abs();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1450 + seed % 750),
    );
    _c.value = (seed % 100) / 100; // phase de départ variable
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget emoji = Text(
      widget.emoji,
      style: TextStyle(fontSize: widget.size, height: 1.0),
    );
    if (MediaQuery.disableAnimationsOf(context)) return emoji;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOut.transform(_c.value);
        final double angle = (t - 0.5) * 0.30; // ±0.15 rad ≈ ±8,5°
        final double scale = 1.0 + t * 0.16; // pulse 1.0 → 1.16
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: emoji,
    );
  }
}

// (Pavé PIN Cinéma supprimé — plus de verrou côté Films/Séries.)
