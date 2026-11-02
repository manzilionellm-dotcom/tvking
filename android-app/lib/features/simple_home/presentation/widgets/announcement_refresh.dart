import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/announcement_repository.dart';

/// Repli du canal temps réel : certains anciens serveurs n'émettent pas
/// encore de signal. L'accueil relit alors l'annonce toutes les cinq secondes,
/// uniquement au premier plan et sur la route visible. Aucun lecteur touché.
class AnnouncementRefresh extends StatefulWidget {
  const AnnouncementRefresh({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;

  @override
  State<AnnouncementRefresh> createState() => _AnnouncementRefreshState();
}

class _AnnouncementRefreshState extends State<AnnouncementRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(AnnouncementRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) _refresh();
  }

  void _refresh() {
    if (!mounted || !widget.enabled) return;
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(AnnouncementRepository.fetchLatest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
