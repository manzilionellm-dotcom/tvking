import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Dependency-free transport contract for deterministic tests.
abstract interface class RealtimeSocket {
  Stream<Object?> get messages;
  void send(String message);
  Future<void> close();
}

typedef Refresh = Future<void> Function();

const Map<String, List<String>> realtimeRefreshMap = <String, List<String>>{
  'source': <String>['sources'],
  'source_clear': <String>['sources'],
  'activate': <String>['status', 'sources'],
  'renew': <String>['status'],
  'expire': <String>['status'],
  'suspend': <String>['status'],
  'resume': <String>['status'],
  'block': <String>['status'],
  'license': <String>['status'],
  'transfer': <String>['status', 'sources'],
  'device_delete': <String>['status', 'sources'],
  'reset': <String>['status', 'sources'],
  'message': <String>['announcements'],
  'banner': <String>['announcements'],
  'theme': <String>['theme'],
  'home': <String>['home'],
  'featured': <String>['featured'],
  'ad': <String>['ad'],
  'force_update': <String>['version'],
  'servers': <String>['servers'],
  'pricing': <String>['pricing'],
  'feedback': <String>['feedback'],
};

/// One socket per process. Per-resource dirty loops ensure an event arriving
/// DURING a refetch gets another pass, not swallowed by an in-flight mutex.
/// Resources run independently: a slow playlist never blocks activation/theme.
class RealtimeService {
  RealtimeService({
    required this.connect,
    required this.refreshers,
    required this.mac,
    this.heartbeat = const Duration(seconds: 15),
    this.deadline = const Duration(seconds: 35),
    this.fallback = const Duration(seconds: 30),
    this.retryBase = const Duration(seconds: 1),
    this.jitter = true,
  });
  final Future<RealtimeSocket> Function() connect;
  final Map<String, Refresh> refreshers;
  final String mac;
  final Duration heartbeat, deadline, fallback, retryBase;
  final bool jitter;
  final StreamController<bool> _states =
      StreamController<bool>.broadcast(sync: true);
  Stream<bool> get states => _states.stream;
  bool get connected => _connected;
  bool _connected = false, _stopped = true;
  int _generation = 0, _attempt = 0;
  RealtimeSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _retry, _pulse, _timeout, _poll;
  final Set<String> _dirty = <String>{};
  final Set<String> _running = <String>{};
  final Map<String, Future<void>> _tasks = <String, Future<void>>{};

  void start() {
    if (!_stopped) return;
    _stopped = false;
    _poll = Timer.periodic(fallback, (_) {
      if (!_connected) refetchAll();
    });
    refetchAll();
    unawaited(_open());
  }

  void resume() {
    if (_stopped) return;
    refetchAll();
    _disconnect();
    _retry?.cancel();
    unawaited(_open());
  }

  void refetchAll() {
    for (final String resource in refreshers.keys) {
      _refresh(resource);
    }
  }

  void _refresh(String resource) {
    if (_stopped || !refreshers.containsKey(resource)) return;
    _dirty.add(resource);
    if (!_running.add(resource)) return;
    _tasks[resource] = _drain(resource);
  }

  Future<void> _drain(String resource) async {
    try {
      do {
        _dirty.remove(resource);
        try {
          await refreshers[resource]!();
        } catch (_) {/* independent best effort */}
      } while (!_stopped && _dirty.contains(resource));
    } finally {
      _running.remove(resource);
      _tasks.remove(resource);
    }
  }

  Future<void> get idle async {
    while (_tasks.isNotEmpty) {
      await Future.wait(_tasks.values.toList());
    }
  }

  void handleMessage(Object? raw) {
    if (_stopped || raw is! String || raw.length > 8192) return;
    Map<String, dynamic> event;
    try {
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return;
      event = value;
    } catch (_) {
      return;
    }
    if (event['v'] != 1) return;
    if (event['type'] == 'hello') {
      _timeout?.cancel();
      _timeout = Timer(deadline, _disconnect);
      if (!_connected) {
        _attempt = 0;
        _connected = true;
        _states.add(true);
        refetchAll(); // no replay assumptions: full resync after every reconnect
      }
      return;
    }
    if (!_connected || (event['mac'] != null && event['mac'] != mac)) return;
    final List<String>? resources = realtimeRefreshMap[event['type']];
    if (resources == null) return;
    for (final String resource in resources) {
      _refresh(resource);
    }
  }

  Future<void> _open() async {
    if (_stopped || _socket != null) return;
    final int owner = ++_generation;
    try {
      bool abandoned = false;
      final Future<RealtimeSocket> pending = connect();
      unawaited(pending.then<void>((RealtimeSocket socket) async {
        if (abandoned) await _closeQuietly(socket);
      }, onError: (Object _, StackTrace __) {}));
      final RealtimeSocket socket = await pending.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          abandoned = true;
          throw TimeoutException('Realtime handshake');
        },
      );
      if (_stopped || owner != _generation) {
        await _closeQuietly(socket);
        return;
      }
      _socket = socket;
      _subscription =
          socket.messages.listen(handleMessage, onError: (Object _) {
        if (owner == _generation) _disconnect();
      }, onDone: () {
        if (owner == _generation) _disconnect();
      });
      _timeout = Timer(deadline, _disconnect);
      socket.send('{"v":1,"type":"hello"}');
      _pulse = Timer.periodic(heartbeat, (_) {
        try {
          socket.send('{"v":1,"type":"hello"}');
        } catch (_) {
          _disconnect();
        }
      });
    } catch (_) {
      if (owner == _generation) _disconnect();
    }
  }

  static Future<void> _closeQuietly(RealtimeSocket socket) async {
    try {
      await socket.close();
    } catch (_) {/* transport already gone */}
  }

  void _disconnect() {
    ++_generation;
    _subscription?.cancel();
    _subscription = null;
    final RealtimeSocket? old = _socket;
    _socket = null;
    if (old != null) unawaited(_closeQuietly(old));
    _pulse?.cancel();
    _timeout?.cancel();
    _retry?.cancel();
    if (_connected) {
      _connected = false;
      _states.add(false);
    }
    if (_stopped) return;
    final int base =
        min(30000, retryBase.inMilliseconds * (1 << min(_attempt++, 5)));
    final int extra = jitter ? Random().nextInt(max(1, base ~/ 4)) : 0;
    _retry =
        Timer(Duration(milliseconds: base + extra), () => unawaited(_open()));
  }

  Future<void> stop() async {
    _stopped = true;
    _poll?.cancel();
    _disconnect();
    await idle;
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }
}
