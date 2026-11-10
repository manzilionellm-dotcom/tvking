import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../profiles/data/active_profile.dart';
import '../core/tv_app_tokens.dart';
import '../data/vip_countries_first_use.dart';

/// Habille le bouton existant sans modifier sa taille, son focus ou sa place.
/// La bulle est une couche temporaire sans capture de touches ni de clics.
class TvVipCountriesFirstUse extends StatefulWidget {
  const TvVipCountriesFirstUse({
    super.key,
    required this.available,
    required this.playing,
    required this.onOpen,
    required this.builder,
    this.store,
  });

  final bool available;
  final bool playing;
  final VoidCallback? onOpen;
  final Widget Function(VoidCallback? open) builder;
  final VipCountriesFirstUse? store;

  @override
  State<TvVipCountriesFirstUse> createState() => _TvVipCountriesFirstUseState();
}

class _TvVipCountriesFirstUseState extends State<TvVipCountriesFirstUse>
    with WidgetsBindingObserver {
  final _overlay = OverlayPortalController();
  final _anchor = LayerLink();
  late final Listenable _changes = Listenable.merge([
    ActiveProfile.instance.listenable,
    RemoteSourceRepository.importing,
    RemoteSourceRepository.manualImporting,
    RemoteSourceRepository.syncing,
  ]);
  String? _profile;
  bool? _seen;
  bool _attempted = false;
  bool _scheduled = false;
  int _generation = 0;
  Timer? _hideTimer;

  VipCountriesFirstUse get _store =>
      widget.store ?? VipCountriesFirstUse.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() {});
  }

  bool get _eligible {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return widget.available &&
        widget.onOpen != null &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        !widget.playing &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        !RemoteSourceRepository.importing.value &&
        !RemoteSourceRepository.manualImporting.value &&
        // Le dernier progrès peut rester sur « saving » après un échec.
        // Seuls les jobs actifs empêchent la découverte des pays disponibles.
        !RemoteSourceRepository.syncing.value;
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _evaluate();
    });
  }

  void _evaluate() {
    final id = ActiveProfile.instance.id;
    if (_profile != id) {
      _hide();
      _profile = id;
      _seen = null;
      _attempted = false;
      final generation = ++_generation;
      _store.hasSeen(id).then((seen) {
        if (!mounted ||
            generation != _generation ||
            id != ActiveProfile.instance.id) {
          return;
        }
        setState(() => _seen = seen);
      }).catchError((Object _) {
        // Une préférence indisponible ne doit jamais bloquer Direct.
        if (mounted &&
            generation == _generation &&
            id == ActiveProfile.instance.id) {
          setState(() => _seen = false);
        }
      });
      return;
    }
    if (!_eligible) {
      _hide();
      return;
    }
    if (_seen == false && !_attempted) {
      _attempted = true;
      _overlay.show();
    }
  }

  void _displayed(String profile) {
    if (!mounted ||
        !_overlay.isShowing ||
        !_eligible ||
        profile != _profile ||
        profile != ActiveProfile.instance.id) {
      return;
    }
    _seen = true;
    unawaited(_store.markSeen(profile).catchError((Object _) {}));
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) _hide();
    });
  }

  void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_overlay.isShowing) {
      if (_seen != true) _attempted = false;
      _overlay.hide();
    }
  }

  void _open() {
    _attempted = true;
    _seen = true;
    _hide();
    final profile = ActiveProfile.instance.id;
    unawaited(_store.markSeen(profile).catchError((Object _) {}));
    widget.onOpen?.call();
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inscription au statut de la route : ouvrir le lecteur/le sélecteur
    // masque la bulle ; un écran couvert ne consomme pas le premier usage.
    ModalRoute.isCurrentOf(context);
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        _schedule();
        return OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (context) {
            final profile = _profile;
            if (profile == null || !_eligible) return const SizedBox.shrink();
            final palette = TvAppTokens.of(context);
            final text = context.l10n.vipCountriesFirstUseHint;
            return Positioned.fill(
              child: IgnorePointer(
                child: Stack(children: [
                  CompositedTransformFollower(
                    link: _anchor,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    followerAnchor: Alignment.topLeft,
                    offset: const Offset(0, 8),
                    child: _DisplayedHint(
                      key: ValueKey(profile),
                      onDisplayed: () => _displayed(profile),
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          width: 300,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: palette.bg.withValues(alpha: 0.97),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: palette.accentBright
                                    .withValues(alpha: 0.65)),
                          ),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.arrow_upward_rounded,
                                size: 18, color: palette.accentBright),
                            const SizedBox(height: 6),
                            Text(text,
                                textAlign: TextAlign.center,
                                style: palette.ui(16, color: palette.text)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
          child: CompositedTransformTarget(
            link: _anchor,
            child: widget.builder(widget.onOpen == null ? null : _open),
          ),
        );
      },
    );
  }
}

/// Le marqueur n'est écrit qu'après le montage réel de la couche visible.
class _DisplayedHint extends StatefulWidget {
  const _DisplayedHint(
      {super.key, required this.onDisplayed, required this.child});
  final VoidCallback onDisplayed;
  final Widget child;
  @override
  State<_DisplayedHint> createState() => _DisplayedHintState();
}

class _DisplayedHintState extends State<_DisplayedHint> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDisplayed();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
