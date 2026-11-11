import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../profiles/data/active_profile.dart';
import '../../security/data/parental_controls.dart';

/// Barrière placée au-dessus du Navigator : ni route précédente, ni raccourci
/// vocal, ni miniature ne peut rester monté pendant une restriction inconnue.
/// Le délai de démarrage n'ouvre jamais cette barrière.
class TvParentalGate extends StatefulWidget {
  const TvParentalGate({super.key, required this.child});
  final Widget child;

  @override
  State<TvParentalGate> createState() => _TvParentalGateState();
}

class _TvParentalGateState extends State<TvParentalGate> {
  final _controls = ParentalControls.instance;
  StreamSubscription<List<Channel>>? _catalog;
  bool _opened = false;
  bool _holdOneFrame = false;
  bool _scheduled = false;
  int _classification = 0;
  List<Channel>? _classifying;
  late String _context;

  String get _currentContext => '${ActiveProfile.instance.id}:'
      '${ActiveProfile.instance.scopeListenable.value}:'
      '${_controls.kidsMode.value}';

  @override
  void initState() {
    super.initState();
    _context = _currentContext;
    if (!AppPlatform.isZuno) return;
    _controls.readiness.addListener(_changed);
    _controls.kidsMode.addListener(_changed);
    ActiveProfile.instance.listenable.addListener(_changed);
    ActiveProfile.instance.scopeListenable.addListener(_changed);
    _catalog =
        PlaylistRepository.instance.channelsStream.listen((_) => _classify());
    _classify();
  }

  void _changed() {
    if (!mounted) return;
    final next = _currentContext;
    if (_opened && (!_controls.contentReady || next != _context)) {
      // Une nouvelle Key ne suffit pas : Navigator possède une GlobalKey,
      // qui pourrait déplacer son ancien état sous la nouvelle branche.
      // Une image sans sous-arbre assure sa destruction avant réouverture.
      _holdOneFrame = true;
    }
    _context = next;
    setState(() {});
    _classify();
  }

  void _classify() {
    if (!AppPlatform.isZuno ||
        !_controls.contentReady ||
        !_controls.kidsMode.value) {
      ++_classification;
      _classifying = null;
      return;
    }
    final repo = PlaylistRepository.instance;
    final snapshot = repo.currentChannels;
    if (identical(snapshot, _classifying) ||
        !snapshot.any((c) => !ChannelPrecompute.isDone(c))) {
      return;
    }
    _classifying = snapshot;
    final pending = snapshot
        .where((c) => !ChannelPrecompute.isDone(c))
        .toList(growable: false);
    final token = ++_classification;
    unawaited(ChannelPrecompute.run(snapshot,
            cancelled: () =>
                !mounted || token != _classification || !_controls.contentReady)
        .then((_) {
      if (!mounted ||
          token != _classification ||
          !identical(snapshot, repo.currentChannels)) {
        return;
      }
      _classifying = null;
      if (pending.any(ChannelPrecompute.isDone)) {
        repo.notifyClassifiedSnapshot();
      }
    }));
  }

  @override
  void dispose() {
    ++_classification;
    _catalog?.cancel();
    _controls.readiness.removeListener(_changed);
    _controls.kidsMode.removeListener(_changed);
    ActiveProfile.instance.listenable.removeListener(_changed);
    ActiveProfile.instance.scopeListenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isZuno) return widget.child;
    if (_holdOneFrame && !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _holdOneFrame = false;
          _scheduled = false;
        });
      });
    }
    if (!_holdOneFrame && _controls.contentReady) {
      _opened = true;
      return widget.child;
    }
    final failed = _controls.readiness.value == ParentalReadiness.failed;
    return ColoredBox(
      color: AppColors.stealthBlack,
      child: Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!failed)
            const CircularProgressIndicator(color: AppColors.stealthPlatinum),
          const SizedBox(height: 24),
          Text(context.l10n.subLoading, style: AppTextStyles.tvNotice),
          if (failed)
            TextButton(
              autofocus: true,
              onPressed: () => unawaited(_controls.retry()),
              child:
                  Text(context.l10n.buttonRetry, style: AppTextStyles.tvNotice),
            ),
        ],
      )),
    );
  }
}
