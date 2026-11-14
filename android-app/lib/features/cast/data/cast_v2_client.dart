import 'dart:async';
import 'dart:io';

import 'cast_v2_codec.dart';

typedef CastV2Connector = Future<Socket> Function(String host, int port);

/// Émetteur réseau local. Le certificat auto-signé est accepté UNIQUEMENT
/// sur cette socket du récepteur Cast : aucun HttpClient global modifié.
class CastV2Client {
  CastV2Client(
      {CastV2Connector? connector,
      this.timeout = const Duration(seconds: 15),
      this.onPlayerState,
      this.onDisconnected})
      : _connector = connector ?? _connect;
  static Future<Socket> _connect(String host, int port) =>
      SecureSocket.connect(host, port,
          onBadCertificate: (_) => true, timeout: const Duration(seconds: 8));
  final CastV2Connector _connector;
  final Duration timeout;
  final void Function(String state)? onPlayerState;
  final void Function()? onDisconnected;
  final StreamController<CastV2Message> _messages =
      StreamController<CastV2Message>.broadcast(sync: true);
  final CastV2FrameDecoder _decoder = CastV2FrameDecoder();
  Socket? _socket;
  Timer? _heartbeat;
  DateTime _lastReceived = DateTime.now();
  int _requestId = 0;
  bool _closed = false;
  String? _transportId;
  int? _mediaSessionId;

  Future<void> open(String host, int port) async {
    if (_closed || _socket != null) {
      throw StateError('Cast session already used');
    }
    final Socket socket = await _connector(host, port);
    if (_closed) {
      socket.destroy();
      throw StateError('Cast cancelled');
    }
    _socket = socket;
    _lastReceived = DateTime.now();
    socket.listen((List<int> chunk) {
      try {
        for (final CastV2Message message in _decoder.add(chunk)) {
          _receive(message);
        }
      } on Object catch (_) {
        _fail(const FormatException('Invalid Cast response'));
      }
    },
        onError: (Object _) =>
            _fail(const SocketException('Cast connection lost')),
        onDone: () => _fail(const SocketException('Cast connection closed')));
    _send(CastV2Commands.connection, <String, dynamic>{'type': 'CONNECT'});
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastReceived) >
          const Duration(seconds: 20)) {
        _fail(const SocketException('Cast heartbeat timeout'));
      } else {
        _send(CastV2Commands.heartbeat, <String, dynamic>{'type': 'PING'});
      }
    });
    final CastV2Message reply = await _request(
        CastV2Commands.receiver, <String, dynamic>{
      'type': 'LAUNCH',
      'appId': CastV2Commands.defaultReceiver
    });
    final Object? apps = (reply.payload['status'] as Map?)?['applications'];
    if (apps is List) {
      for (final Object? app in apps) {
        if (app is Map &&
            app['appId'] == CastV2Commands.defaultReceiver &&
            app['transportId'] is String) {
          _transportId = app['transportId'] as String;
          break;
        }
      }
    }
    if (_transportId == null) throw StateError('Cast receiver did not launch');
    _send(CastV2Commands.connection, <String, dynamic>{'type': 'CONNECT'},
        destination: _transportId!);
  }

  void _receive(CastV2Message message) {
    if (_closed) return;
    _lastReceived = DateTime.now();
    if (message.namespace == CastV2Commands.heartbeat &&
        message.payload['type'] == 'PING') {
      _send(CastV2Commands.heartbeat, <String, dynamic>{'type': 'PONG'},
          destination: message.sourceId);
    }
    if (message.namespace == CastV2Commands.connection &&
        message.payload['type'] == 'CLOSE') {
      _fail(const SocketException('Cast receiver ended session'));
      return;
    }
    if (message.namespace == CastV2Commands.media) {
      final Object? statuses = message.payload['status'];
      if (statuses is List && statuses.isNotEmpty && statuses.first is Map) {
        final Map<dynamic, dynamic> status = statuses.first as Map;
        if (status['mediaSessionId'] is num) {
          _mediaSessionId = (status['mediaSessionId'] as num).toInt();
        }
        if (status['playerState'] is String) {
          onPlayerState?.call(status['playerState'] as String);
        }
      }
    }
    _messages.add(message);
  }

  Future<CastV2Message> _request(String namespace, Map<String, dynamic> payload,
      {String destination = 'receiver-0', bool awaitPlaying = false}) async {
    if (_closed || _socket == null) throw StateError('Cast is disconnected');
    final int id = ++_requestId;
    bool loadAcknowledged = false;
    final Completer<CastV2Message> done = Completer<CastV2Message>();
    late final StreamSubscription<CastV2Message> subscription;
    subscription = _messages.stream.listen((CastV2Message message) {
      if (done.isCompleted || message.namespace != namespace) return;
      final Map<String, dynamic> body = message.payload;
      final bool matches = body['requestId'] == id;
      if (matches &&
          <String>{
            'LAUNCH_ERROR',
            'LOAD_FAILED',
            'LOAD_CANCELLED',
            'INVALID_REQUEST',
            'INVALID_PLAYER_STATE'
          }.contains(body['type'])) {
        done.completeError(
            StateError('Cast command rejected: ${body['type']}'));
        return;
      }
      if (!awaitPlaying) {
        if (matches) done.complete(message);
        return;
      }
      if (matches && body['type'] == 'MEDIA_STATUS') loadAcknowledged = true;
      if (!loadAcknowledged) return;
      final Object? statuses = body['status'];
      if (statuses is List && statuses.isNotEmpty && statuses.first is Map) {
        final Map<dynamic, dynamic> status = statuses.first as Map;
        if (status['playerState'] == 'PLAYING') done.complete(message);
        if (status['playerState'] == 'IDLE' &&
            status['idleReason'] == 'ERROR') {
          done.completeError(
              StateError('Cast receiver cannot play this format'));
        }
      }
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    }, onDone: () {
      if (!done.isCompleted) {
        done.completeError(StateError('Cast disconnected'));
      }
    });
    try {
      _send(namespace, <String, dynamic>{...payload, 'requestId': id},
          destination: destination);
      return await done.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> load(
      {required String url,
      required String contentType,
      required String title,
      String? imageUrl,
      bool live = true}) async {
    final String? destination = _transportId;
    if (destination == null) throw StateError('Cast receiver not ready');
    await _request(
        CastV2Commands.media,
        CastV2Commands.load(
            requestId: 0,
            url: url,
            contentType: contentType,
            title: title,
            imageUrl: imageUrl,
            live: live),
        destination: destination,
        awaitPlaying: true);
  }

  Future<void> command(String type) async {
    final int? session = _mediaSessionId;
    final String? destination = _transportId;
    if (session == null || destination == null) {
      throw StateError('No Cast media session');
    }
    await _request(CastV2Commands.media,
        <String, dynamic>{'type': type, 'mediaSessionId': session},
        destination: destination);
  }

  void _send(String namespace, Map<String, dynamic> payload,
      {String destination = 'receiver-0'}) {
    if (_closed || _socket == null) throw StateError('Cast disconnected');
    _socket!.add(CastV2Message(
            namespace: namespace, payload: payload, destinationId: destination)
        .encodeFrame());
  }

  void _fail(Object error) {
    if (_closed) return;
    if (_messages.hasListener) _messages.addError(error);
    close();
    onDisconnected?.call();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _socket?.destroy();
    _socket = null;
    unawaited(_messages.close());
  }
}
