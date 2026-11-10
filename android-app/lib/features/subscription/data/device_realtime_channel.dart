// Canal de réveil du panel actuel : statut authentifié → ticket à usage
// unique → WebSocket. Une notification ne contient ni source ni ordre à
// accuser : la veille relit les données concernées avec ses clients habituels.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'subscription_backend.dart';

/// L'identité d'installation doit venir du stockage déjà utilisé par l'app.
/// Le canal ne crée ni ne remplace une clé connue du serveur.
@immutable
class DeviceRealtimeCredentials {
  const DeviceRealtimeCredentials({
    required this.deviceKey,
    required this.deviceId,
  });

  final String deviceKey;
  final String deviceId;

  bool get _valid =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(deviceKey) &&
      deviceId.isNotEmpty &&
      deviceId.length <= 256 &&
      !RegExp(r'[\x00-\x20\x7f]').hasMatch(deviceId);
}

/// Données normalisées et immuables. Les révisions servent seulement à
/// dédupliquer les réveils de cette connexion, jamais aux accusés legacy.
@immutable
class DeviceRealtimeWake {
  DeviceRealtimeWake({
    Iterable<String> kinds = const <String>[],
    Map<String, int> revisions = const <String, int>{},
    this.resync = false,
  })  : kinds = Set<String>.unmodifiable(kinds),
        revisions = Map<String, int>.unmodifiable(revisions);

  final Set<String> kinds;
  final Map<String, int> revisions;

  /// Le serveur ne rejoue pas les événements manqués : chaque ouverture
  /// demande une relecture, même quand aucun nouveau message n'arrive.
  final bool resync;
}

const Set<String> _deviceRealtimeKinds = <String>{
  'source',
  'source_clear',
  'activate',
  'renew',
  'expire',
  'suspend',
  'resume',
  'block',
  'license',
  'transfer',
  'device_delete',
  'message',
  'theme',
  'home',
  'force_update',
  'featured',
  'ad',
  'pricing',
  'feedback',
  'servers',
  'banner',
  'reset',
};

/// Le contrat v1 utilise `version`, pas `seq` ni `order_id`. La MAC
/// facultative est contrôlée AVANT tout avancement du curseur.
DeviceRealtimeWake? parseDeviceRealtimeWake(String raw, {required String mac}) {
  if (raw.length > 16384) return null;
  try {
    final Object? value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['v'] is! int ||
        value['v'] != 1) {
      return null;
    }
    if (value.containsKey('mac') && value['mac'] != mac) return null;
    final Object? kind = value['type'];
    final Object? revision = value['version'];
    if (kind is! String || !_deviceRealtimeKinds.contains(kind)) return null;
    if (revision is! int || revision <= 0) return null;
    return DeviceRealtimeWake(
      kinds: <String>[kind],
      revisions: <String, int>{kind: revision},
    );
  } catch (_) {
    return null;
  }
}

/// Une instance vit jusqu'à stop(). Les callbacks métier ne bloquent jamais
/// la lecture de la prise : une playlist lente ne retient pas une suspension.
class DeviceRealtimeChannel {
  DeviceRealtimeChannel({
    required this.mac,
    required this.credentialProvider,
    required this.onWake,
    required this.alive,
    this.onConnectionChanged,
    String baseUrl = kSubscriptionBaseUrl,
    http.Client? client,
    Future<WebSocket> Function(Uri uri)? connect,
    this.requestTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.helloInterval = const Duration(seconds: 25),
  })  : _base = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _connect = connect ?? ((uri) => WebSocket.connect(uri.toString()));

  final String mac;
  final Future<DeviceRealtimeCredentials?> Function() credentialProvider;
  final FutureOr<void> Function(DeviceRealtimeWake wake) onWake;
  final bool Function() alive;
  final void Function(bool connected)? onConnectionChanged;
  final Duration requestTimeout;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Duration helloInterval;
  final Uri _base;
  final http.Client _client;
  final bool _ownsClient;
  final Future<WebSocket> Function(Uri uri) _connect;

  bool _stopped = false;
  bool _open = false;
  int _attempt = 0;
  WebSocket? _socket;
  Future<void>? _running;
  Timer? _hello;
  Timer? _retry;
  Completer<void>? _retryDone;

  bool get open => _open;
  bool get _going => !_stopped && alive();

  void start() => unawaited(run());

  Future<void> run() {
    if (_stopped) return Future<void>.value();
    return _running ??= _runLoop();
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _attempt++;
    _hello?.cancel();
    _retry?.cancel();
    final waiting = _retryDone;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    _setOpen(false);
    _close(_socket);
    if (_ownsClient) _client.close();
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    try {
      onConnectionChanged?.call(value);
    } catch (error) {
      _log('connexion', error);
    }
  }

  void _wake(DeviceRealtimeWake wake) {
    if (!_going) return;
    unawaited(Future<void>.sync(() => onWake(wake)).catchError((Object error) {
      // La veille possède les reprises métier. Une erreur de son callback
      // ne doit pas interrompre le canal ou masquer le prochain réveil.
      _log('réveil', error);
    }));
  }

  Future<void> _runLoop() async {
    var delay = retryDelay;
    while (_going) {
      final int attempt = ++_attempt;
      try {
        final Uri? uri = await _socketUri();
        if (!_going) break;
        if (uri == null) throw const _DeviceRealtimeUnavailable();
        final socket = await _connect(uri).then((socket) {
          // Une ouverture arrivée après timeout/stop ne doit pas laisser
          // une prise orpheline ou réveiller une veille déjà arrêtée.
          if (!_going || attempt != _attempt) {
            _close(socket);
            throw const _DeviceRealtimeUnavailable();
          }
          return socket;
        }).timeout(requestTimeout);
        _socket = socket;
        if (!_going) break;
        _setOpen(true);
        delay = retryDelay;
        // Le compteur du Durable Object peut repartir de zéro après son
        // remplacement. On déduplique uniquement dans cette connexion.
        int cursor = 0;
        _wake(DeviceRealtimeWake(resync: true));
        _hello = Timer.periodic(helloInterval, (_) {
          if (!_going) {
            _close(socket);
            return;
          }
          try {
            socket.add('{"v":1,"type":"hello"}');
          } catch (error) {
            _log('hello', error);
            _close(socket);
          }
        });
        await for (final dynamic message in socket) {
          if (!_going) break;
          if (message is! String) continue;
          final wake = parseDeviceRealtimeWake(message, mac: mac);
          if (wake == null) continue;
          final revision = wake.revisions.values.single;
          if (revision <= cursor) continue;
          cursor = revision;
          _wake(wake);
        }
      } catch (error) {
        // Ne jamais journaliser l'URI du ticket, le Bearer ou le secret.
        if (_going) _log('canal', error);
      } finally {
        _attempt++;
        _hello?.cancel();
        _hello = null;
        _setOpen(false);
        _close(_socket);
        _socket = null;
      }
      if (!_going) break;
      await _pause(delay);
      delay = Duration(
        milliseconds:
            (delay.inMilliseconds * 2).clamp(0, maxRetryDelay.inMilliseconds),
      );
    }
  }

  Future<Uri?> _socketUri() async {
    if (!const <String>{'http', 'https'}.contains(_base.scheme) ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty) {
      return null;
    }
    final credentials = await credentialProvider().timeout(requestTimeout);
    if (!_going || credentials == null || !credentials._valid) return null;
    final status = await _request(
      'GET',
      _base.resolve('/api/status/${Uri.encodeComponent(mac)}'),
      <String, String>{
        'Accept': 'application/json',
        'X-Device-Key': credentials.deviceKey,
        'X-Device-Id': credentials.deviceId,
      },
    );
    if (!_going || status.statusCode != 200) return null;
    final token = _jsonString(status.body, 'device_token');
    // Une clé inconnue/incompatible donne normalement un statut 200 sans
    // jeton. On garde le repli HTTP ; aucun ré-enrôlement n'est tenté ici.
    if (token == null ||
        token.length > 8192 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(token)) {
      return null;
    }
    final response = await _request(
      'POST',
      _base.resolve('/api/device-rt/ticket'),
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (!_going || response.statusCode != 200) return null;
    final ticket = _jsonString(response.body, 'ticket');
    if (ticket == null ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(ticket)) {
      return null;
    }
    return Uri(
      scheme: _base.scheme == 'https' ? 'wss' : 'ws',
      host: _base.host,
      port: _base.hasPort ? _base.port : null,
      path: '/api/device-rt/ws',
      queryParameters: <String, String>{'ticket': ticket},
    );
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, String> headers,
  ) {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    // Un redirect n'a jamais le droit d'emporter les preuves vers un
    // autre hôte. Chaque étape possède exclusivement ses propres headers.
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(requestTimeout);
  }

  static String? _jsonString(String body, String key) {
    try {
      final Object? value = jsonDecode(body);
      if (value is! Map<String, dynamic>) return null;
      final Object? text = value[key];
      return text is String && text.isNotEmpty ? text : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pause(Duration duration) async {
    if (!_going) return;
    final done = Completer<void>();
    _retryDone = done;
    _retry = Timer(duration, done.complete);
    await done.future;
    _retryDone = null;
    _retry = null;
  }

  static void _close(WebSocket? socket) {
    if (socket == null) return;
    try {
      unawaited(socket.close().catchError((Object _) {}));
    } catch (_) {
      // Une fermeture déjà entamée ne doit pas relancer la boucle arrêtée.
    }
  }

  static void _log(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('[DeviceRealtime] $operation : ${error.runtimeType}');
    }
  }
}

class _DeviceRealtimeUnavailable implements Exception {
  const _DeviceRealtimeUnavailable();
}
