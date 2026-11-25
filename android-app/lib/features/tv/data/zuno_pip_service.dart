import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../cast/data/cast_platform.dart';

/// Fenêtre flottante Android du lecteur local. Son canal est volontairement
/// distinct du service historique qui maintient les sessions Cast en vie.
class ZunoPipService extends ChangeNotifier {
  ZunoPipService._({required this.enabled, required MethodChannel channel})
      : _channel = channel {
    if (enabled) _channel.setMethodCallHandler(_onNativeCall);
  }

  @visibleForTesting
  ZunoPipService.forTesting({
    required bool enabled,
    MethodChannel channel = const MethodChannel('com.sevenmotion.zuno/pip'),
  }) : this._(enabled: enabled, channel: channel);

  static ZunoPipService? _instance;
  @visibleForTesting
  static ZunoPipService? debugOverride;
  static ZunoPipService get instance =>
      debugOverride ??
      (_instance ??= ZunoPipService._(
        enabled: !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            CastPlatform.canSendFromZuno,
        channel: const MethodChannel('com.sevenmotion.zuno/pip'),
      ));

  final bool enabled;
  final MethodChannel _channel;
  bool _inPip = false;
  bool _visible = true;
  bool _disposed = false;
  int _revision = 0;
  int _request = 0;
  int _owner = 0;
  bool? _active;
  String? _ratio;

  bool get isInPipMode => _inPip;
  bool get isVisible => _visible;

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!enabled || _disposed) return null;
    try {
      return await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Ancien binaire ou PiP refusée : le lecteur garde son cycle normal.
      return null;
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (_disposed || call.method != 'onPipModeChanged') return;
    final Object? data = call.arguments;
    if (data is Map && data['inPip'] is bool && data['visible'] is bool) {
      _revision++;
      _apply(data['inPip'] as bool, data['visible'] as bool);
    }
  }

  void _apply(bool inPip, bool visible) {
    if (_inPip == inPip && _visible == visible) return;
    _inPip = inPip;
    _visible = visible;
    notifyListeners();
  }

  /// Un événement Android plus récent gagne toujours contre une réponse
  /// asynchrone. De même, une ancienne requête ne remplace pas la suivante.
  Future<bool> _refresh() async {
    final int revision = _revision;
    final int request = ++_request;
    final Object? data = await _invoke<Object>('getPipState');
    if (_disposed || revision != _revision || request != _request) return true;
    if (data is! Map || data['inPip'] is! bool || data['visible'] is! bool) {
      return false;
    }
    _apply(data['inPip'] as bool, data['visible'] as bool);
    return true;
  }

  ZunoPipPlayback acquire({
    required void Function(bool forceStop) onSuspend,
    required VoidCallback onResume,
    required VoidCallback onModeChanged,
    required ValueChanged<bool> onVisibilityChanged,
  }) {
    final int owner = ++_owner;
    _request++;
    _active = null;
    _ratio = null;
    return ZunoPipPlayback._(
        this, owner, onSuspend, onResume, onModeChanged, onVisibilityChanged);
  }

  void _setActive(int owner, bool active) {
    if (_disposed || owner != _owner || _active == active) return;
    _active = active;
    unawaited(
        _invoke<void>('setPlaybackActive', <String, Object>{'active': active}));
  }

  void _setRatio(int owner, int width, int height) {
    if (_disposed || owner != _owner || width <= 0 || height <= 0) return;
    final String ratio = '$width/$height';
    if (_ratio == ratio) return;
    _ratio = ratio;
    unawaited(_invoke<void>('setAspectRatio', <String, Object>{
      'num': width,
      'den': height,
    }));
  }

  @override
  void dispose() {
    _disposed = true;
    _owner++;
    if (enabled) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Bail du lecteur affiché. Un écran qui se ferme ne peut ni désarmer la PiP,
/// ni suspendre le lecteur qui vient de le remplacer.
class ZunoPipPlayback {
  ZunoPipPlayback._(this._service, this._owner, this._onSuspend, this._onResume,
      this._onModeChanged, this._onVisibilityChanged) {
    _service.addListener(_onNativeState);
    _service._setActive(_owner, false);
  }

  final ZunoPipService _service;
  final int _owner;
  final void Function(bool forceStop) _onSuspend;
  final VoidCallback _onResume;
  final VoidCallback _onModeChanged;
  final ValueChanged<bool> _onVisibilityChanged;
  bool _disposed = false;
  bool _suspended = false;
  bool _forcedSuspend = false;
  int _lifecycleRevision = 0;

  bool get _owns => !_disposed && _owner == _service._owner;
  bool get isInPipMode => _service.isInPipMode;
  bool get isVisible => _service.isVisible;

  void update(
      {required bool playing,
      required bool casting,
      int width = 0,
      int height = 0}) {
    if (!_owns) return;
    _service._setActive(_owner, playing && !casting);
    _service._setRatio(_owner, width, height);
  }

  void _suspend({required bool forceStop}) {
    if (!_owns || (_suspended && (!forceStop || _forcedSuspend))) return;
    _suspended = true;
    _forcedSuspend = forceStop;
    // Une ancienne réponse absente a pu demander une simple pause. Quand
    // Android confirme onStop, renforcer cette pause en arrêt complet.
    _onSuspend(forceStop);
  }

  void _resume() {
    if (!_owns || !_suspended) return;
    _suspended = false;
    _forcedSuspend = false;
    _onResume();
  }

  void _onNativeState() {
    if (!_owns) return;
    _onModeChanged();
    _onVisibilityChanged(isVisible);
    // onStop, y compris écran éteint avec le drapeau PiP toujours vrai,
    // signifie réellement invisible. Aucun repli ne doit laisser du son.
    if (!isVisible) {
      _suspend(forceStop: true);
    } else {
      _resume();
    }
  }

  Future<void> onLifecycle(AppLifecycleState state) async {
    if (!_owns || state == AppLifecycleState.inactive) return;
    final int revision = ++_lifecycleRevision;
    if (state == AppLifecycleState.resumed) {
      _service._request++;
      _onVisibilityChanged(true);
      _resume();
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (_service.enabled) {
      final bool known = await _service._refresh();
      if (!_owns || revision != _lifecycleRevision) return;
      // Une activité visible peut être en train d'entrer ou sortir de PiP :
      // le drapeau physique seul arrive parfois une frame trop tard.
      if (known && isVisible && state != AppLifecycleState.detached) return;
      _onVisibilityChanged(false);
      _suspend(forceStop: known && !isVisible);
    } else {
      _onVisibilityChanged(false);
      _suspend(forceStop: false);
    }
  }

  void dispose() {
    if (_disposed) return;
    if (_owns) _service._setActive(_owner, false);
    _disposed = true;
    _lifecycleRevision++;
    _service.removeListener(_onNativeState);
  }
}
