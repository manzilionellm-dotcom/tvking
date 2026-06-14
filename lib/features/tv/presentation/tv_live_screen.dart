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
  StreamSubscription<List<String>>? _recentSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  List<String> _trending = TrendingRepository.instance.current;
  List<String> _recentIds = RecentlyWatchedRepository.instance.current;
  List<Channel> _all = const <Channel>[];
  List<String> _cats = const <String>[];
  String? _selectedCat;
  bool _heroShown = false;

  /// Pseudo-catégories en TÊTE de liste (sentinelles internes, pas de vraies
  /// catégories) : Tendances (les plus regardées EN CE MOMENT) puis Favoris.
  static const String _kTrendCat = 'k.trending';
  static const String _kRecentCat = 'k.recent';
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
      if (mounted) setState(() {
        _favIds = ids;
        _recompute();
      });
    });
    // Tendances en direct : la catégorie « 🔥 Tendances » se met à jour seule.
    TrendingRepository.instance.start();
    _trendSub = TrendingRepository.instance.stream.listen((List<String> names) {
      if (mounted) setState(() {
        _trending = names;
        _recompute();
      });
    });
    // Historique « 🕒 Récemment » en direct.
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((List<String> ids) {
      if (mounted) setState(() {
        _recentIds = ids;
        _recompute();
      });
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
    _recentSub?.cancel();
    TrendingRepository.instance.stop();
    _syncTimer?.cancel();
    super.dispose();
  }

  // ----- État dérivé MÉMOÏSÉ (scalabilité grosses listes) -----
  // On NE recalcule PAS ces listes à chaque frame : seulement quand une source
  // change (chaînes, favoris, tendances, historique, catégorie). Indispensable
  // pour rester fluide même avec des dizaines/centaines de milliers de chaînes.
  List<Channel> _favCh = const <Channel>[];
  List<Channel> _trendCh = const <Channel>[];
  List<Channel> _recentCh = const <Channel>[];
  List<String> _dispCats = const <String>[];
  List<Channel> _shownList = const <Channel>[];

  /// Recalcule TOUT l'état dérivé à partir des sources. Appelé UNIQUEMENT quand
  /// une source change — jamais dans build().
  void _recompute() {
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
      final Map<String, Channel> byId = <String, Channel>{
        for (final Channel c in _all) c.id: c,
      };
      _recentCh = <Channel>[
        for (final String id in _recentIds)
          if (byId[id] != null) byId[id]!,
      ];
    }
    // Tendances (ordre de popularité, match par nom insensible à la casse).
    if (_trending.isEmpty || _all.isEmpty) {
      _trendCh = const <Channel>[];
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
    // Catégories affichées (pseudo-catégories non vides en tête).
    final List<String> cats = <String>[];
    if (_trendCh.isNotEmpty) cats.add(_kTrendCat);
    if (_favCh.isNotEmpty) cats.add(_kFavCat);
    if (_recentCh.isNotEmpty) cats.add(_kRecentCat);
    cats.addAll(_cats);
    _dispCats = cats;
    // Grille affichée selon la catégorie sélectionnée.
    if (_selectedCat == _kTrendCat) {
      _shownList = _trendCh;
    } else if (_selectedCat == _kFavCat) {
      _shownList = _favCh;
    } else if (_selectedCat == _kRecentCat) {
      _shownList = _recentCh;
    } else if (_selectedCat == null) {
      _shownList = _all;
    } else {
      _shownList = _all
          .where((Channel c) => _catOf(c) == _selectedCat)
          .toList(growable: false);
    }
  }

  /// Sélectionne une catégorie (focus/OK) puis recalcule la grille.
  void _select(String cat) {
    if (_selectedCat == cat) return;
    setState(() {
      _selectedCat = cat;
      _recompute();
    });
  }


  /// Vrai pour les pseudo-catégories spéciales (teintées or).
  bool _isSpecialCat(String cat) =>
      cat == _kTrendCat || cat == _kFavCat || cat == _kRecentCat;

  /// Libellé visible d'une catégorie (les sentinelles sont traduites/ornées).
  String _catLabel(BuildContext context, String cat) {
    if (cat == _kTrendCat) return '🔥 Tendances';
    if (cat == _kFavCat) return '★ ${context.l10n.navFavorites}';
    if (cat == _kRecentCat) return '🕒 Récemment';
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
    // Ordre des catégories = ordre d'APPARITION ; dédup via Set (O(1)) pour
    // rester rapide même sur de très grandes listes (évite un contains O(n²)).
    final List<String> cats = <String>[];
    final Set<String> seenCats = <String>{};
    for (final Channel c in live) {
      final String cat = _catOf(c);
      if (seenCats.add(cat)) cats.add(cat);
    }
    if (!mounted) return;
    setState(() {
      _all = live;
      _cats = cats;
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
                  final List<String> cats = _dispCats;
                  return ListView.builder(
                    itemCount: cats.length,
                    itemBuilder: (BuildContext context, int i) {
                    final String cat = cats[i];
                    final bool sel = cat == _selectedCat;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TvFocusBuilder(
                        autofocus: i == 0 && !_heroShown,
                        scale: TvFocusScale.medium,
                        onSelect: () => _select(cat),
                        builder: (BuildContext context, bool focused) {
                          // Le focus met à jour la grille (preview live).
                          if (focused && _selectedCat != cat) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _select(cat);
                            });
                          }
                          // FOCUS UNIQUE (règle #3) : seul l'élément RÉELLEMENT
                          // focus (D-pad) porte l'or — bordure 2 px + texte or
                          // + ombre. La catégorie « active mais pas focus » =
                          // gris neutre discret, JAMAIS d'or, jamais de scale.
                          final bool active = sel && !focused;
                          final Color bg = (focused || active)
                              ? TvTokens.sel
                              : Colors.transparent;
                          final Color fg = focused
                              ? TvTokens.goldBright
                              : (active ? TvTokens.text : TvTokens.muted);
                          return Container(
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius:
                                  BorderRadius.circular(TvTokens.rMenuItem),
                              border: focused
                                  ? Border.all(
                                      color: TvTokens.gold,
                                      width: TvDimens.focusOutline)
                                  : null,
                              boxShadow: focused
                                  ? <BoxShadow>[
                                      BoxShadow(
                                        color: TvTokens.gold
                                            .withValues(alpha: 0.22),
                                        blurRadius: TvDimens.focusGlowBlur,
                                        spreadRadius: TvDimens.focusGlowSpread,
                                      ),
                                    ]
                                  : null,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text(
                              _catLabel(context, cat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: TvDimens.titleS,
                                  fontWeight: (focused || active)
                                      ? FontWeight.w700
                                      : FontWeight.w600,
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
        Expanded(child: _ChannelGrid(channels: _shownList)),
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
        mainAxisExtent: 152,
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
    final bool fav = FavoritesRepository.instance.current.contains(channel.id);
    final _ParsedName p = _parseName(channel);
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
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Tuile : logo centré (avec padding) sur fond #161514, bordure
            // blanche 5 % → les logos ne « flottent » plus comme des stickers.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: TvTokens.tile,
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                  border: Border.all(color: TvTokens.tileBorder),
                ),
                padding: const EdgeInsets.all(14),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _Logo(channel: channel)),
                    if (fav)
                      const Positioned(
                        top: 0,
                        right: 0,
                        child: Icon(Icons.favorite_rounded,
                            size: 14, color: TvTokens.gold),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
            // Badges qualité/tags PROPRES, après le nom (jamais dans le titre).
            if (p.badges.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 5,
                children: <Widget>[
                  for (final String b in p.badges.take(3)) _TagBadge(label: b),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Extrait les tags du nom (qualité + VIP/RAW/60 FPS/HEVC/LIVE) en casse
  /// uniforme et renvoie le nom NETTOYÉ + la liste des badges.
  static _ParsedName _parseName(Channel c) {
    String n = c.cleanName;
    final List<String> badges = <String>[];
    const List<(String, String)> rules = <(String, String)>[
      ('4K', r'\b(4K|UHD|2160P?)\b'),
      ('FHD', r'\b(FHD|1080P?)\b'),
      ('HD', r'\bHD\b'),
      ('HEVC', r'\b(HEVC|H\.?265)\b'),
      ('60 FPS', r'\b60\s?FPS\b'),
      ('VIP', r'\bVIP\b'),
      ('RAW', r'\bRAW\b'),
      ('LIVE', r'\bLIVE\b'),
    ];
    for (final (String label, String pattern) in rules) {
      final RegExp re = RegExp(pattern, caseSensitive: false);
      if (re.hasMatch(n)) {
        badges.add(label);
        n = n.replaceAll(re, ' ');
      }
    }
    n = n
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s|·\-–]+'), '')
        .replaceAll(RegExp(r'[\s|·\-–]+$'), '')
        .trim();
    if (n.isEmpty) n = c.cleanName; // garde-fou : jamais de nom vide
    return _ParsedName(n, badges);
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
              color: TvTokens.gold)),
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
      // Skeleton Maison Noir : pendant le chargement, on montre les initiales
      // très discrètes plutôt qu'un trou vide (finition premium).
      loadingBuilder: (BuildContext context, Widget child,
          ImageChunkEvent? progress) {
        if (progress == null) return child;
        return Opacity(opacity: 0.35, child: fallback);
      },
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
