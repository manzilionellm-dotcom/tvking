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

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/trending_repository.dart';
import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';
import 'tv_shell.dart';

class TvLiveScreen extends StatefulWidget {
  const TvLiveScreen({super.key});

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  StreamSubscription<List<Channel>>? _sub;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<String>>? _trendSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  List<String> _trending = TrendingRepository.instance.current;
  List<Channel> _all = const <Channel>[];
  List<String> _cats = const <String>[];
  String? _selectedCat;
  bool _heroShown = false;

  /// Pseudo-catégories en TÊTE de liste (sentinelles internes, pas de vraies
  /// catégories) : Tendances (les plus regardées EN CE MOMENT) puis Favoris.
  static const String _kTrendCat = 'k.trending';
  static const String _kFavCat = '★ favoris'; // ★ favoris (clé interne)

  // Re-synchro de la source poussée par le panel. CRUCIAL : sans ça, l'app
  // ne récupérait la source qu'au tout 1er démarrage ; si le revendeur
  // activait/poussait APRÈS, la TV restait « Aucune chaîne » jusqu'au
  // redémarrage. Ici on re-tente tant qu'on n'a aucune chaîne.
  Timer? _syncTimer;
  bool _syncing = false;
  RemoteSyncResult? _lastSync;
  String _mac = '…'; // adresse de CET appareil (à montrer si pas de chaînes)

  @override
  void initState() {
    super.initState();
    _ingest(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen(_ingest);
    // Favoris en direct : la catégorie « ★ Favoris » se met à jour toute seule.
    FavoritesRepository.instance.initialize();
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    // Tendances en direct : la catégorie « 🔥 Tendances » se met à jour seule.
    TrendingRepository.instance.start();
    _trendSub = TrendingRepository.instance.stream.listen((List<String> names) {
      if (mounted) setState(() => _trending = names);
    });
    // MAC affichée sur l'état vide : sans elle, impossible de savoir à quel
    // appareil pousser une source dans le panel.
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    _kickSourceSync(); // tout de suite à l'ouverture de l'écran
    _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_all.isEmpty) _kickSourceSync();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _favSub?.cancel();
    _trendSub?.cancel();
    TrendingRepository.instance.stop();
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Chaînes favorites présentes dans la playlist courante (ordre playlist).
  List<Channel> get _favChannels =>
      _all.where((Channel c) => _favIds.contains(c.id)).toList(growable: false);

  /// Chaînes tendance présentes dans la playlist locale, dans l'ORDRE de
  /// popularité renvoyé par le backend (match par nom, insensible à la casse).
  List<Channel> get _trendingChannels {
    if (_trending.isEmpty || _all.isEmpty) return const <Channel>[];
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
    return out;
  }

  /// Catégories affichées : « 🔥 Tendances » puis « ★ Favoris » (si non vides)
  /// en tête, puis les vraies catégories de la source.
  List<String> get _displayCats {
    final List<String> out = <String>[];
    if (_trendingChannels.isNotEmpty) out.add(_kTrendCat);
    if (_favChannels.isNotEmpty) out.add(_kFavCat);
    out.addAll(_cats);
    return out;
  }

  /// Vrai pour les pseudo-catégories spéciales (teintées or).
  bool _isSpecialCat(String cat) => cat == _kTrendCat || cat == _kFavCat;

  /// Libellé visible d'une catégorie (les sentinelles sont traduites/ornées).
  String _catLabel(BuildContext context, String cat) {
    if (cat == _kTrendCat) return '🔥 Tendances';
    if (cat == _kFavCat) return '★ ${context.l10n.navFavorites}';
    return cat;
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

  void _ingest(List<Channel> channels) {
    final List<Channel> live =
        channels.where((Channel c) => c.isLive).toList(growable: false);
    // Ordre des catégories = ordre d'APPARITION dans la source (1re vue).
    final List<String> cats = <String>[];
    for (final Channel c in live) {
      final String cat = _catOf(c);
      if (!cats.contains(cat)) cats.add(cat);
    }
    if (!mounted) return;
    setState(() {
      _all = live;
      _cats = cats;
      _selectedCat ??= cats.isNotEmpty ? cats.first : null;
      // On ne réinitialise PAS si l'utilisateur est sur « ★ Favoris » (pseudo-
      // catégorie absente de `cats`) — sinon un refresh de la source l'en
      // ferait sortir.
      if (_selectedCat != null &&
          !_isSpecialCat(_selectedCat!) &&
          !cats.contains(_selectedCat)) {
        _selectedCat = cats.isNotEmpty ? cats.first : null;
      }
    });
  }

  List<Channel> get _shown {
    if (_selectedCat == _kTrendCat) return _trendingChannels;
    if (_selectedCat == _kFavCat) return _favChannels;
    return _selectedCat == null
        ? _all
        : _all
            .where((Channel c) => _catOf(c) == _selectedCat)
            .toList(growable: false);
  }

  // Dernière chaîne regardée (1er id de l'historique présent dans la
  // playlist courante) → « Continuer à regarder ».
  Channel? _lastWatched() {
    for (final String id in RecentlyWatchedRepository.instance.current) {
      for (final Channel c in _all) {
        if (c.id == id) return c;
      }
    }
    return null;
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

    final Channel? last = _lastWatched();
    _heroShown = last != null;

    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ----- Catégories -----
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(context.l10n.tvNavLive,
                    style: TextStyle(
                        fontSize: TvDimens.displayS,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
              ),
              Expanded(
                child: Builder(builder: (BuildContext context) {
                  final List<String> cats = _displayCats;
                  return ListView.builder(
                    itemCount: cats.length,
                    itemBuilder: (BuildContext context, int i) {
                    final String cat = cats[i];
                    final bool sel = cat == _selectedCat;
                    final bool isFav = _isSpecialCat(cat);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TvFocusBuilder(
                        autofocus: i == 0 && !_heroShown,
                        scale: TvFocusScale.large,
                        onSelect: () => setState(() => _selectedCat = cat),
                        builder: (BuildContext context, bool focused) {
                          // Le focus met à jour la grille (preview live).
                          if (focused && _selectedCat != cat) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedCat = cat);
                            });
                          }
                          // Maison Noir : fond `--sel` + texte or au focus/
                          // actif. JAMAIS de bloc blanc plein (interdit #4).
                          final bool hl = focused || sel;
                          final Color bg = hl ? TvTokens.sel : Colors.transparent;
                          // Les favoris restent toujours teintés or (repère).
                          final Color fg = hl
                              ? TvTokens.goldBright
                              : (isFav ? TvTokens.gold : TvTokens.muted);
                          return Container(
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius:
                                  BorderRadius.circular(TvDimens.cardRadius),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text(
                              _catLabel(context, cat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: TvDimens.titleS,
                                  fontWeight:
                                      isFav ? FontWeight.w800 : FontWeight.w600,
                                  color: fg),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(width: TvDimens.gutter),
        // ----- Grille de chaînes (virtualisée) -----
        Expanded(child: _ChannelGrid(channels: _shown)),
      ],
    );

    if (last == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ContinueHero(
          channel: last,
          all: _all,
          index: _all.indexOf(last),
        ),
        const SizedBox(height: 16),
        Expanded(child: body),
      ],
    );
  }
}

/// Bandeau « Continuer à regarder » (dernière chaîne), auto-focus.
class _ContinueHero extends StatelessWidget {
  const _ContinueHero(
      {required this.channel, required this.all, required this.index});
  final Channel channel;
  final List<Channel> all;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      scale: TvFocusScale.large,
      baseColor: TvTokens.card,
      onSelect: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(
              channels: all, startIndex: index < 0 ? 0 : index),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.play_circle_fill_rounded,
                color: TvTokens.text, size: 40),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(context.l10n.tvContinueWatching,
                    style: TextStyle(
                        fontSize: TvDimens.caption,
                        letterSpacing: 2,
                        color: TvTokens.mutedDim)),
                const SizedBox(height: 2),
                Text(channel.cleanName,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.channels});
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoChannelInCategory,
            style: TextStyle(
                fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 132,
        crossAxisSpacing: TvDimens.gutter,
        mainAxisSpacing: TvDimens.gutter,
      ),
      itemCount: channels.length,
      itemBuilder: (BuildContext context, int i) =>
          _ChannelCard(channel: channels[i], all: channels, index: i),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard(
      {required this.channel, required this.all, required this.index});
  final Channel channel;
  final List<Channel> all;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      onSelect: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TvPlayerScreen(channels: all, startIndex: index),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(child: _Logo(channel: channel)),
            const SizedBox(height: 8),
            Text(
              channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Center(
      child: Text(channel.initials,
          style: TextStyle(
              fontSize: TvDimens.title,
              fontWeight: FontWeight.w800,
              color: TvTokens.muted)),
    );
    final String? url = channel.logoUrl;
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
      // Décodage hors-UI + petite taille mémoire (perf §10).
      cacheWidth: 200,
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
