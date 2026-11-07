import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/ads/data/startup_ad_repository.dart';
import '../../features/ads/presentation/startup_ad_screen.dart';
import '../../features/about/data/force_update_checker.dart';
import '../../features/about/presentation/forced_update_screen.dart';

/// Shared TV/mobile live controls; frequency is honoured, removal stops video.
class PanelControlGate extends StatefulWidget {
  const PanelControlGate({super.key, required this.child});
  final Widget child;
  @override
  State<PanelControlGate> createState() => _PanelControlGateState();
}

class _PanelControlGateState extends State<PanelControlGate> {
  bool _showAd = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    StartupAdRepository.instance.addListener(_adChanged);
    ForceUpdateChecker.instance.requiredUpdate.addListener(_versionChanged);
    unawaited(StartupAdRepository.instance.fetch().then((_) => _adChanged()));
    unawaited(ForceUpdateChecker.instance.refresh());
  }

  void _versionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _adChanged() async {
    final int revision = ++_revision;
    final bool show = await StartupAdRepository.instance.shouldShow();
    if (!mounted || revision != _revision) return;
    setState(() => _showAd = show);
  }

  @override
  void dispose() {
    StartupAdRepository.instance.removeListener(_adChanged);
    ForceUpdateChecker.instance.requiredUpdate.removeListener(_versionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ForceUpdateChecker.instance.requiredUpdate.value) {
      return ForcedUpdateScreen(
          onRetry: () => unawaited(ForceUpdateChecker.instance.refresh()));
    }
    if (_showAd) {
      return StartupAdScreen(
          key: ValueKey<int>(_revision),
          config: StartupAdRepository.instance.config,
          onDone: () {
            unawaited(StartupAdRepository.instance.markShown());
            if (mounted) setState(() => _showAd = false);
          });
    }
    return widget.child;
  }
}
