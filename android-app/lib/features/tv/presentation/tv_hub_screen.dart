// =========================================================
//  tv_hub_screen.dart — Accueil « lanceur » (grille de tuiles) pour la TV
// =========================================================
//  Disposition classique d'un lecteur de box, entièrement en design maison
//  (TvTokens + logo Zuno) :
//
//    ┌───────────────────────────────────────────────────────────┐
//    │ [logo]                                    📶  12:34  25/09  │  barre haut
//    │        ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐             │
//    │        │Direct│ │Films│ │Séries│ │Serveur│ │Régl.│          │  5 tuiles
//    │        └─────┘ └─────┘ └─────┘ └─────┘ └─────┘             │
//    │ CODE MK:..    Essai — 6 j    utilisateur@serveur           │  barre bas
//    └───────────────────────────────────────────────────────────┘
//
//  Chaque tuile ouvre un écran EXISTANT en pleine page (Retour = revenir au
//  lanceur). La licence (essai / payé / gelé / banni) est DÉCIDÉE par le panel
//  (via TvGate/SubscriptionState) et seulement AFFICHÉE ici — saisir une source
//  ne débloque pas l'accueil sans licence valide. Aucune couleur/taille en dur.
// =========================================================
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/app/boot_guard.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_app.dart';
import 'tv_components.dart';
import 'tv_diagnostic_screen.dart';
import 'tv_live_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';
import 'tv_sources_screen.dart';

/// Les 5 tuiles de l'accueil, de gauche à droite.
enum _Tile { live, films, series, server, settings }

class TvHubScreen extends StatefulWidget {
  const TvHubScreen({super.key});
  @override
  State<TvHubScreen> createState() => _TvHubScreenState();
}

class _TvHubScreenState extends State<TvHubScreen> {
  // Barre du haut : heure/date (tick 20 s) + réseau.
  Timer? _clock;
  DateTime _now = DateTime.now();
  List<ConnectivityResult> _conn = const <ConnectivityResult>[];
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Barre du bas : MAC + serveur actif (rafraîchi quand les sources changent).
  String _mac = '…';
  StreamSubscription<List<Channel>>? _srcSub;

  // ----- « Source-push » DIRECT depuis le panel (décision du propriétaire) -----
  // Le revendeur assigne l'abonnement (Xtream/M3U) à la MAC dans le panel et
  // la box doit recevoir les chaînes SANS que le client ne fasse rien :
  //   • tant qu'on est sur l'accueil, on re-demande la source au panel toutes
  //     les 20 s (simple GET, dédupliqué côté repo → gratuit s'il n'y a rien
  //     de neuf) ;
  //   • dès que la licence passe à « actif » (activation dans le panel), on
  //     synchronise IMMÉDIATEMENT (sans attendre le tick) ;
  //   • quand les PREMIÈRES chaînes arrivent (0 → n) alors que l'accueil est
  //     au premier plan, on ouvre Direct tout seul : « le fil entre
  //     directement ». Une seule fois par session d'accueil, jamais si le
  //     client est déjà dans un autre écran.
  Timer? _sourcePoll;
  bool _hadChannels = false;
  bool _autoOpened = false;
  bool _wasActive = false;
  static const Duration _kSourcePollEvery = Duration(seconds: 20);

  // Accès CACHÉ au diagnostic : séquence D-pad HAUT-HAUT-BAS-BAS.
  static const List<bool> _diagSeq = <bool>[true, true, false, false];
  final List<bool> _diagBuf = <bool>[];
  bool _diagOpen = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    _hadChannels = PlaylistRepository.instance.currentChannels.isNotEmpty;
    _wasActive = _isActive(SubscriptionState.instance.status);
    SubscriptionState.instance.addListener(_onLicenseChange);
    _srcSub =
        PlaylistRepository.instance.channelsStream.listen(_onChannels);
    _initConnectivity();
    // Source-push direct : voir le commentaire du champ _sourcePoll.
    if (!BootGuard.instance.safeMode) {
      _sourcePoll = Timer.periodic(_kSourcePollEvery, (_) {
        if (mounted) RemoteSourceRepository.sync();
      });
    }
  }

  static bool _isActive(SubscriptionStatus s) =>
      s == SubscriptionStatus.paid || s == SubscriptionStatus.trialActive;

  /// Licence changée : rafraîchit la barre du bas ET, si l'accès vient de
  /// s'ouvrir (activation faite dans le panel), va chercher la source TOUT DE
  /// SUITE — c'est le moment exact où le revendeur vient d'assigner l'abonnement.
  void _onLicenseChange() {
    final bool active = _isActive(SubscriptionState.instance.status);
    if (active && !_wasActive && !BootGuard.instance.safeMode) {
      RemoteSourceRepository.sync();
    }
    _wasActive = active;
    _onChange();
  }

  /// Chaînes changées : rafraîchit la barre du bas et, à la PREMIÈRE arrivée
  /// de chaînes (0 → n) pendant que l'accueil est visible, ouvre Direct.
  void _onChannels(List<Channel> channels) {
    final bool has = channels.isNotEmpty;
    final bool firstArrival = has && !_hadChannels;
    _hadChannels = has;
    _onChange();
    if (!firstArrival || _autoOpened || !mounted) return;
    // Uniquement si l'accueil est l'écran du dessus (le client n'est pas dans
    // Réglages/Serveur/lecteur) : on ne vole jamais un écran en cours.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _autoOpened = true;
    _openTile(_Tile.live);
  }

  Future<void> _initConnectivity() async {
    try {
      _conn = await Connectivity().checkConnectivity();
      if (mounted) setState(() {});
      _connSub = Connectivity()
          .onConnectivityChanged
          .listen((List<ConnectivityResult> r) {
        if (mounted) setState(() => _conn = r);
      });
    } catch (_) {}
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _connSub?.cancel();
    _srcSub?.cancel();
    _sourcePoll?.cancel();
    SubscriptionState.instance.removeListener(_onLicenseChange);
    super.dispose();
  }

  IconData get _netIcon {
    if (_conn.contains(ConnectivityResult.ethernet)) {
      return Icons.settings_ethernet_rounded;
    }
    if (_conn.contains(ConnectivityResult.wifi)) return Icons.wifi_rounded;
    if (_conn.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt_rounded;
    }
    return Icons.wifi_off_rounded;
  }

  ({String label, Color color}) _license(BuildContext context) {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (label: context.l10n.tvStatusPaid, color: TvTokens.success);
      case SubscriptionStatus.trialActive:
        return (
          label: context.l10n
              .tvStatusTrial(SubscriptionState.instance.trialDaysRemaining),
          color: TvTokens.accentBright,
        );
      case SubscriptionStatus.trialExpired:
        return (label: context.l10n.tvStatusTrialExpired, color: TvTokens.live);
      case SubscriptionStatus.frozen:
        return (label: context.l10n.tvStatusFrozen, color: TvTokens.live);
      case SubscriptionStatus.banned:
        return (label: context.l10n.tvStatusBanned, color: TvTokens.live);
      case SubscriptionStatus.unknown:
        return (label: '', color: TvTokens.mutedDim);
    }
  }

  String get _activeSource {
    try {
      final List<Playlist> all = PlaylistRepository.instance.currentPlaylists;
      if (all.isEmpty) return '';
      final Playlist p =
          all.firstWhere((Playlist x) => x.isActive, orElse: () => all.first);
      final String user = (p.xtreamUsername ?? '').trim();
      final String one = user.isEmpty ? p.name : '$user · ${p.name}';
      // Mode fusion (TV) : toutes les listes sont affichées ensemble → on
      // l'indique sobrement (« … +2 ») sans changer la mise en page.
      return all.length > 1 ? '$one +${all.length - 1}' : one;
    } catch (_) {
      return '';
    }
  }

  void _openTile(_Tile t) {
    Widget page;
    switch (t) {
      case _Tile.live:
        page = const TvLiveScreen();
      case _Tile.server:
        page = const TvSourcesScreen();
      case _Tile.settings:
        page = const TvSettingsScreen();
      case _Tile.films:
        page = TvEmptyState(
          icon: Icons.movie_rounded,
          title: context.l10n.tvNavFilms,
          subtitle: context.l10n.tvComingSoon,
        );
      case _Tile.series:
        page = TvEmptyState(
          icon: Icons.video_library_rounded,
          title: context.l10n.tvNavSeries,
          subtitle: context.l10n.tvComingSoon,
        );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TvShell(child: page)),
    );
  }

  ({IconData icon, String label}) _tileMeta(BuildContext c, _Tile t) {
    switch (t) {
      case _Tile.live:
        return (icon: Icons.live_tv_rounded, label: c.l10n.tvNavLive);
      case _Tile.films:
        return (icon: Icons.movie_rounded, label: c.l10n.tvNavFilms);
      case _Tile.series:
        return (icon: Icons.video_library_rounded, label: c.l10n.tvNavSeries);
      case _Tile.server:
        return (icon: Icons.dns_rounded, label: 'Serveur');
      case _Tile.settings:
        return (icon: Icons.settings_rounded, label: c.l10n.tvNavSettings);
    }
  }

  Future<void> _onBack() async {
    final String? action = await showExitDialog(context);
    if (!mounted) return;
    if (action == 'restart') {
      RestartWidget.restart(context);
    } else if (action == 'quit') {
      await SystemNavigator.pop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    final bool up =
        k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp;
    final bool down = k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown;
    if (!up && !down) {
      if (_diagBuf.isNotEmpty) _diagBuf.clear();
      return KeyEventResult.ignored;
    }
    _diagBuf.add(up);
    if (_diagBuf.length > _diagSeq.length) _diagBuf.removeAt(0);
    bool match = _diagBuf.length == _diagSeq.length;
    for (int i = 0; match && i < _diagSeq.length; i++) {
      if (_diagBuf[i] != _diagSeq[i]) match = false;
    }
    if (match) {
      _diagBuf.clear();
      if (!_diagOpen) {
        _diagOpen = true;
        Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(
                builder: (_) => const TvDiagnosticScreen()))
            .then((_) => _diagOpen = false);
      }
    }
    return KeyEventResult.ignored;
  }

  String get _time =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final String localeName = Localizations.localeOf(context).toString();
    final String date = DateFormat('EEE d MMM', localeName).format(_now);
    final ({String label, Color color}) lic = _license(context);
    final String src = _activeSource;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _onBack();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: TvShell(
          // Fond PLEIN ÉCRAN (image de marque, cf. pubspec) + voile sombre pour
          // garder les textes lisibles, puis le contenu dans les marges TV.
          applySafeArea: false,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset('assets/branding/tv_hub_background.jpg',
                  fit: BoxFit.cover),
              DecoratedBox(
                  decoration:
                      BoxDecoration(color: TvTokens.bg.withValues(alpha: 0.35))),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: TvDimens.safeH, vertical: TvDimens.safeV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---------- BARRE DU HAUT ----------
              Row(
                children: <Widget>[
                  const TvLogo(width: 150),
                  const Spacer(),
                  Icon(_netIcon, size: 22, color: TvTokens.muted),
                  const SizedBox(width: 16),
                  Text(_time, style: TvTokens.display(22, color: TvTokens.text)),
                  const SizedBox(width: 12),
                  Text(date, style: TvTokens.ui(15, color: TvTokens.mutedDim)),
                ],
              ),
              // ---------- TUILES (centrées) ----------
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < _Tile.values.length; i++) ...<Widget>[
                        _HubTile(
                          meta: _tileMeta(context, _Tile.values[i]),
                          autofocus: i == 0,
                          onSelect: () => _openTile(_Tile.values[i]),
                        ),
                        if (i != _Tile.values.length - 1)
                          const SizedBox(width: 22),
                      ],
                    ],
                  ),
                ),
              ),
              // ---------- BARRE DU BAS ----------
              Row(
                children: <Widget>[
                  Text('${context.l10n.tvActivationCodeLabel} : ',
                      style: TvTokens.ui(14, color: TvTokens.mutedDim)),
                  Text(_mac,
                      style: TvTokens.mono(16, color: TvTokens.accentBright)),
                  const Spacer(),
                  if (lic.label.isNotEmpty)
                    Text(lic.label,
                        style: TvTokens.ui(15,
                            weight: FontWeight.w600, color: lic.color)),
                  if (src.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 18),
                    Text(src, style: TvTokens.ui(14, color: TvTokens.mutedDim)),
                  ],
                ],
              ),
            ],
          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une tuile carrée focusable (icône + libellé). Focus = fond braise + lueur.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.meta,
    required this.onSelect,
    this.autofocus = false,
  });
  final ({IconData icon, String label}) meta;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          width: 190,
          height: 190,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
                color: focused ? TvTokens.accent : TvTokens.line,
                width: focused ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(meta.icon,
                  size: 64,
                  color: focused ? TvTokens.onAccent : TvTokens.accent),
              const SizedBox(height: 18),
              Text(meta.label,
                  style: TvTokens.ui(20, weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
    );
  }
}
