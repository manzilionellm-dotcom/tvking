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
import '../../security/data/biometric_auth.dart';
import '../data/cinema_lock.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  /// Code pays sélectionné (`null` = on est sur la grille des pays).
  String? _countryCode;
  String _countryFlag = '';
  String _countryName = '';

  @override
  void initState() {
    super.initState();
    FavoritesRepository.instance.initialize();
    RecentlyWatchedRepository.instance.initialize();
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
            return Column(
              children: <Widget>[
                _buildHeader(channels.isNotEmpty),
                Expanded(
                  child: channels.isEmpty
                      ? EmptyStateView(
                          onAddPlaylist: () => showSourceChoiceSheet(context),
                        )
                      : (_countryCode == null
                          ? _buildCountryGrid(channels)
                          : _buildCountryDetail(channels)),
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
              _countryCode == null
                  ? context.l10n.simpleChooseCountry
                  : '$_countryFlag  $_countryName',
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

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1,
      ),
      itemCount: countries.length,
      itemBuilder: (BuildContext context, int i) {
        final _Country c = countries[i];
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() {
              _countryCode = c.code;
              _countryFlag = c.flag;
              _countryName = c.name;
            }),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(c.flag, style: const TextStyle(fontSize: 50)),
                const SizedBox(height: 8),
                Text(
                  c.name,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(context.l10n.channelCount(c.count),
                    style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----- Niveau 2 : détail d'un pays -----
  Widget _buildCountryDetail(List<Channel> allChannels) {
    // Chaînes de ce pays uniquement.
    final List<Channel> channels = allChannels
        .where((Channel c) => (c.country?.code ?? 'intl') == _countryCode)
        .toList();

    List<Channel> byGenre(Set<ChannelGenre> genres) =>
        channels.where((Channel c) => genres.contains(c.genre)).toList();

    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> favSnap) {
        final Set<String> favs = favSnap.data ?? <String>{};
        return StreamBuilder<List<String>>(
          stream: RecentlyWatchedRepository.instance.stream,
          initialData: RecentlyWatchedRepository.instance.current,
          builder: (BuildContext context, AsyncSnapshot<List<String>> recSnap) {
            final List<String> recentIds = recSnap.data ?? const <String>[];

            // Récents/favoris filtrés à ce pays, en gardant l'ordre.
            final Map<String, Channel> byId = <String, Channel>{
              for (final Channel c in channels) c.id: c,
            };
            final List<Channel> recent = <Channel>[
              for (final String id in recentIds)
                if (byId[id] != null) byId[id]!,
            ];
            final List<Channel> favList = <Channel>[
              for (final Channel c in channels)
                if (favs.contains(c.id)) c,
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              physics: const BouncingScrollPhysics(),
              children: <Widget>[
                _section('🕐 ${context.l10n.simpleRecentlyWatched}',
                    AppColors.info, recent, favs),
                _section('⭐ ${context.l10n.simpleMyFavorites}',
                    AppColors.warning, favList, favs),
                _section('⚽ ${context.l10n.simpleSport}', AppColors.success,
                    byGenre(<ChannelGenre>{ChannelGenre.sports}), favs),
                _section(
                    '🎬 ${context.l10n.simpleEntertainment}',
                    AppColors.warning,
                    byGenre(<ChannelGenre>{
                      ChannelGenre.entertainment,
                      ChannelGenre.music,
                      ChannelGenre.documentary,
                    }),
                    favs),
                _section('📰 ${context.l10n.simpleInfo}', AppColors.info,
                    byGenre(<ChannelGenre>{ChannelGenre.news}), favs),
                _section('🧸 ${context.l10n.simpleKids}', AppColors.accent,
                    byGenre(<ChannelGenre>{ChannelGenre.kids}), favs),
                _section(
                    '📡 ${context.l10n.simpleGeneral}',
                    AppColors.textSecondary,
                    byGenre(<ChannelGenre>{
                      ChannelGenre.other,
                      ChannelGenre.international,
                    }),
                    favs),

                // ----- Zone verrouillée : Cinéma & Séries (+ Adulte) -----
                _buildLockedZone(channels, favs),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLockedZone(List<Channel> channels, Set<String> favs) {
    List<Channel> byGenre(Set<ChannelGenre> genres) =>
        channels.where((Channel c) => genres.contains(c.genre)).toList();

    final List<Channel> cine =
        byGenre(<ChannelGenre>{ChannelGenre.movies});
    final List<Channel> series =
        byGenre(<ChannelGenre>{ChannelGenre.series});
    final List<Channel> adult =
        byGenre(<ChannelGenre>{ChannelGenre.adult});
    if (cine.isEmpty && series.isEmpty && adult.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!CinemaLock.unlockedThisSession) {
      return GestureDetector(
        onTap: _tryUnlockCinema,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 18),
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.live.withValues(alpha: 0.6),
              width: 1.5,
            ),
            color: AppColors.live.withValues(alpha: 0.08),
          ),
          child: Column(
            children: <Widget>[
              const Text('🔒', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text('🍿 ${context.l10n.simpleLockedTitle}',
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 17)),
              const SizedBox(height: 4),
              Text(context.l10n.simpleLockedHint,
                  style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        _section('🍿 ${context.l10n.sectionMovies}', AppColors.live, cine, favs),
        _section('📺 ${context.l10n.sectionSeries}', AppColors.accentBright,
            series, favs),
        if (adult.isNotEmpty)
          _section('🔞 ${context.l10n.sectionAdult}', AppColors.accentMuted,
              adult, favs),
      ],
    );
  }

  Future<void> _tryUnlockCinema() async {
    // 1) Empreinte / Face ID en priorité.
    bool ok = false;
    try {
      if (await BiometricAuth.instance.isSupported()) {
        ok = await BiometricAuth.instance.authenticate(
          reason: context.l10n.simpleUnlockReason,
        );
      }
    } catch (_) {}
    if (ok) {
      CinemaLock.unlockedThisSession = true;
      if (mounted) setState(() {});
      return;
    }
    // 2) Sinon, pavé PIN.
    if (!mounted) return;
    final bool pinOk = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => const _PinPad(),
        ) ??
        false;
    if (pinOk && mounted) setState(() {});
  }

  // ----- Une section (rangée horizontale de tuiles) -----
  Widget _section(
      String title, Color accent, List<Channel> items, Set<String> favs) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: AppTextStyles.headlineMedium.copyWith(fontSize: 17)),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length > 40 ? 40 : items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
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
            icon: Icons.search_rounded,
            label: context.l10n.navSearch,
            active: false,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          _BottomNavItem(
            icon: Icons.favorite_rounded,
            label: context.l10n.navFavorites,
            active: false,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
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
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.accent : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                letterSpacing: 0.4,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent, width: 2),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: channel.hasLogo
                        ? Image.network(
                            channel.logoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                Icon(channel.genre.icon, color: accent),
                          )
                        : Icon(channel.genre.icon, color: accent, size: 30),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      channel.cleanName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 2,
              right: 4,
              child: GestureDetector(
                onTap: onFav,
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 18,
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

/// Pavé numérique pour le code Cinéma & Séries.
class _PinPad extends StatefulWidget {
  const _PinPad();

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _pin = '';
  bool _wrong = false;

  Future<void> _push(String d) async {
    if (_pin.length >= 8) return;
    setState(() {
      _wrong = false;
      _pin += d;
    });
    // On valide automatiquement à partir de 5 chiffres (code par défaut).
    if (_pin.length >= 5) {
      final bool ok = await CinemaLock.verifyPin(_pin);
      if (ok) {
        if (mounted) Navigator.of(context).pop(true);
      } else if (_pin.length >= 8) {
        setState(() {
          _wrong = true;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text('🔒 ${context.l10n.simpleAccessCode}',
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(8, (int i) {
                final bool filled = _pin.length > i;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _wrong
                        ? AppColors.live
                        : (filled ? AppColors.textPrimary : Colors.transparent),
                    border: Border.all(
                      color: _wrong ? AppColors.live : AppColors.border,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            ...<List<String>>[
              <String>['1', '2', '3'],
              <String>['4', '5', '6'],
              <String>['7', '8', '9'],
              <String>['', '0', '⌫'],
            ].map((List<String> row) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((String k) {
                    if (k.isEmpty) {
                      return const SizedBox(width: 76, height: 64);
                    }
                    return Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox(
                        width: 64,
                        height: 56,
                        child: k == '⌫'
                            ? TextButton(
                                onPressed: () => setState(() {
                                  if (_pin.isNotEmpty) {
                                    _pin = _pin.substring(0, _pin.length - 1);
                                  }
                                }),
                                child: const Text('⌫',
                                    style: TextStyle(fontSize: 20)),
                              )
                            : FilledButton(
                                onPressed: () => _push(k),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                  foregroundColor: AppColors.textPrimary,
                                ),
                                child: Text(k,
                                    style: AppTextStyles.headlineMedium
                                        .copyWith(fontSize: 20)),
                              ),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.buttonCancel),
            ),
          ],
        ),
      ),
    );
  }
}
