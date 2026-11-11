// Un seul lecteur fournisseur : les mêmes paquets MPEG-TS alimentent le
// lecteur local et le fichier. Une playlist HLS est une description, jamais
// une vidéo : ses segments sont résolus, contrôlés, puis partagés eux aussi.
// Le démarrage REC est confirmé après une vraie écriture, et sa clôture attend
// le disque. Les URL et en-têtes privés ne figurent jamais dans les erreurs.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'player_settings.dart';

enum RelayStopReason {
  userStopped,
  completed,
  networkError,
  diskError,
  unsupportedStream,
  cancelled,
}

class RelayRecordingException implements Exception {
  const RelayRecordingException(this.reason);
  final RelayStopReason reason;
  @override
  String toString() => 'Recording: ${reason.name}';
}

@immutable
class RelayRecordingResult {
  const RelayRecordingResult(
      {required this.filePath, required this.bytes, required this.reason});
  final String filePath;
  final int bytes;
  final RelayStopReason reason;
  bool get succeeded =>
      reason == RelayStopReason.userStopped ||
      reason == RelayStopReason.completed;
}

typedef RelayFileOpener = Future<RandomAccessFile> Function(File file);

Future<RandomAccessFile> _openRecordingFile(File file) =>
    file.open(mode: FileMode.write);

class LocalStreamRelay {
  LocalStreamRelay._() : this.forTesting();
  static final LocalStreamRelay instance = LocalStreamRelay._();

  /// Durées et ouverture fichier injectables pour simuler les pannes locales.
  /// La production garde les valeurs ci-dessous et le vrai fichier Android.
  @visibleForTesting
  LocalStreamRelay.forTesting({
    Duration firstMediaTimeout = const Duration(seconds: 25),
    Duration networkTimeout = const Duration(seconds: 15),
    Duration retryDelay = const Duration(seconds: 2),
    Duration? playlistPollDelay,
    int maxReconnectFailures = 3,
    RelayFileOpener? openFile,
  })  : _firstMediaTimeout = firstMediaTimeout,
        _networkTimeout = networkTimeout,
        _retryDelay = retryDelay,
        _playlistPollDelay = playlistPollDelay,
        _maxReconnectFailures = maxReconnectFailures,
        _openFile = openFile ?? _openRecordingFile;

  final Duration _firstMediaTimeout;
  final Duration _networkTimeout;
  final Duration _retryDelay;
  final Duration? _playlistPollDelay;
  final int _maxReconnectFailures;
  final RelayFileOpener _openFile;
  HttpServer? _server;
  Future<void>? _serverStarting;
  final Map<String, _RelaySession> _sessions = <String, _RelaySession>{};
  final LinkedHashMap<String, RelayRecordingResult> _finished =
      LinkedHashMap<String, RelayRecordingResult>();

  bool isRecording(String realUrl) =>
      _sessions[realUrl]?.recording?.closing == false;
  bool isRecordingFile(String path) => _sessions.values.any((_RelaySession s) =>
      s.recording?.filePath == path && s.recording?.closing == false);
  int recordedBytes(String realUrl) =>
      _sessions[realUrl]?.recording?.bytes ?? 0;

  Future<String> playUrlFor(String realUrl,
      {Map<String, String> headers = const <String, String>{}}) async {
    _session(realUrl, headers);
    await (_serverStarting ??= _startServer());
    // L'extension décrit le contenu effectivement produit par ce relais,
    // même si la source d'origine est une playlist HLS sans extension.
    return 'http://127.0.0.1:${_server!.port}/stream.ts?u=${Uri.encodeComponent(realUrl)}';
  }

  Future<bool> startRecording(
      {required String realUrl,
      required String filePath,
      Map<String, String> headers = const <String, String>{},
      void Function(RelayRecordingResult result)? onStopped}) async {
    final _RelaySession session = _session(realUrl, headers);
    final _RelayRecording? existing = session.recording;
    if (existing != null && !existing.closing) {
      if (existing.filePath != filePath) {
        throw const RelayRecordingException(RelayStopReason.diskError);
      }
      await existing.started.future;
      return true;
    }
    final File file = File(filePath);
    late final RandomAccessFile handle;
    try {
      await file.parent.create(recursive: true);
      // Un nom déjà utilisé ne doit jamais tronquer un ancien enregistrement.
      if (await file.exists()) {
        throw const FileSystemException('Recording path already exists');
      }
      handle = await _openFile(file);
    } catch (_) {
      throw const RelayRecordingException(RelayStopReason.diskError);
    }
    if (session.closed) {
      await handle.close();
      throw const RelayRecordingException(RelayStopReason.cancelled);
    }
    _finished.remove(realUrl);
    final _RelayRecording recording =
        _RelayRecording(filePath, handle, onStopped);
    session.recording = recording;
    _ensurePump(session);
    try {
      await recording.started.future.timeout(_firstMediaTimeout);
      return true;
    } catch (error) {
      await stopRecordingResult(realUrl, closePlayback: true);
      if (error is RelayRecordingException) rethrow;
      throw const RelayRecordingException(RelayStopReason.networkError);
    }
  }

  Future<int> stopRecording(String realUrl,
      {bool closePlayback = false}) async {
    final RelayRecordingResult result =
        await stopRecordingResult(realUrl, closePlayback: closePlayback);
    if (!result.succeeded && result.reason != RelayStopReason.cancelled) {
      throw RelayRecordingException(result.reason);
    }
    return result.bytes;
  }

  /// closePlayback est utilisé avant de repasser au fournisseur en direct :
  /// la fermeture réseau est attendue, donc jamais deux lectures simultanées.
  Future<RelayRecordingResult> stopRecordingResult(String realUrl,
      {bool closePlayback = false}) async {
    final _RelaySession? session = _sessions[realUrl];
    if (session == null) {
      return _finished[realUrl] ??
          const RelayRecordingResult(
              filePath: '', bytes: 0, reason: RelayStopReason.userStopped);
    }
    session.recording?.explicitStop = true;
    if (closePlayback) _cancelSession(session);
    final RelayRecordingResult? result =
        await _finishRecording(session, RelayStopReason.userStopped);
    if (!session.hasConsumers) _cancelSession(session);
    if (closePlayback || session.closed) await session.pump;
    if (session.closed && identical(_sessions[realUrl], session)) {
      _sessions.remove(realUrl);
    }
    return result ??
        _finished[realUrl] ??
        const RelayRecordingResult(
            filePath: '', bytes: 0, reason: RelayStopReason.userStopped);
  }

  @visibleForTesting
  Future<void> closeForTesting() async {
    for (final String url in _sessions.keys.toList()) {
      await stopRecordingResult(url, closePlayback: true);
    }
    await _server?.close(force: true);
    _server = null;
    _serverStarting = null;
    _finished.clear();
  }

  _RelaySession _session(String url, Map<String, String> headers) {
    _httpUri(url);
    final _RelaySession? previous = _sessions[url];
    if (previous != null && !previous.closed) {
      if (headers.isNotEmpty && !mapEquals(previous.headers, headers)) {
        throw const RelayRecordingException(RelayStopReason.cancelled);
      }
      return previous;
    }
    final _RelaySession session =
        _RelaySession(url, Map<String, String>.of(headers));
    _sessions[url] = session;
    return session;
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) {
      unawaited(_serve(request));
    });
  }

  Future<void> _serve(HttpRequest request) async {
    final String? url = request.uri.queryParameters['u'];
    final _RelaySession? session = _sessions[url];
    if (request.uri.path != '/stream.ts' ||
        session == null ||
        session.closed ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final HttpResponse response = request.response;
    response.headers.contentType = ContentType('video', 'mp2t');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
    response.bufferOutput = false;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    final _PlayerConsumer consumer = _PlayerConsumer(response);
    session.players.add(consumer);
    response.done
        .then((_) => consumer.close())
        .catchError((Object _) => consumer.close());
    try {
      // Le lecteur arrive après la première écriture confirmée : rejouer la
      // petite fenêtre initiale lui fournit aussi les tables PAT/PMT du TS.
      for (final List<int> bytes in session.recent) {
        response.add(bytes);
      }
      _ensurePump(session);
      await consumer.done.future;
    } catch (_) {
      consumer.close();
    } finally {
      session.players.remove(consumer);
      if (!session.hasConsumers) _cancelSession(session);
    }
  }

  void _ensurePump(_RelaySession session) {
    if (session.pump != null || session.closed) return;
    session.pump = _run(session);
  }

  Future<void> _run(_RelaySession session) async {
    RelayStopReason reason = RelayStopReason.userStopped;
    int failures = 0;
    try {
      while (!session.closed && session.hasConsumers) {
        final int before = session.mediaBytes;
        try {
          final _Fetched response = await _get(session, _httpUri(session.url));
          final _Probe probe = await _probe(response);
          if (probe.playlist != null) {
            await _hls(session, probe.playlist!, response.uri);
            reason = RelayStopReason.completed;
            break;
          }
          await _consumeTs(session, probe.iterator!, probe.prefix);
          if (session.closed) break;
          // Un EOF après des médias est normal sur certains directs. Un
          // serveur qui renvoie des corps vides ne remet pas le budget à zéro.
          failures = session.mediaBytes > before ? 0 : failures + 1;
        } on RelayRecordingException catch (error) {
          reason = error.reason;
          break;
        } catch (_) {
          if (session.closed) break;
          failures++;
        }
        if (failures >= _maxReconnectFailures) {
          reason = RelayStopReason.networkError;
          break;
        }
        await _wait(session, _retryDelay * (failures + 1));
      }
    } catch (_) {
      if (!session.closed) reason = RelayStopReason.networkError;
    } finally {
      _cancelSession(session);
      await _finishRecording(session, reason);
      if (identical(_sessions[session.url], session)) {
        _sessions.remove(session.url);
      }
    }
  }

  Future<_Fetched> _get(_RelaySession session, Uri uri) async {
    if (session.closed) {
      throw const RelayRecordingException(RelayStopReason.cancelled);
    }
    final HttpClient client = session.client ??= (HttpClient()
      ..connectionTimeout = _networkTimeout
      ..idleTimeout = const Duration(seconds: 20)
      ..maxConnectionsPerHost = 1
      ..autoUncompress = true
      ..userAgent = PlayerSettings.instance.userAgent);
    final HttpClientRequest request =
        await client.getUrl(uri).timeout(_networkTimeout);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    for (final MapEntry<String, String> header in session.headers.entries) {
      if (<String>{'host', 'connection', 'content-length', 'transfer-encoding'}
          .contains(header.key.toLowerCase())) {
        continue;
      }
      request.headers.set(header.key, header.value);
    }
    final HttpClientResponse response =
        await request.close().timeout(_networkTimeout);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>().timeout(_networkTimeout);
      throw const RelayRecordingException(RelayStopReason.networkError);
    }
    Uri resolved = uri;
    for (final RedirectInfo redirect in response.redirects) {
      resolved = resolved.resolveUri(redirect.location);
    }
    return _Fetched(response, resolved);
  }

  Future<_Probe> _probe(_Fetched fetched) async {
    final StreamIterator<List<int>> iterator =
        StreamIterator<List<int>>(fetched.response.timeout(_networkTimeout));
    final List<int> prefix = <int>[];
    try {
      while (await iterator.moveNext()) {
        prefix.addAll(iterator.current);
        final String head = utf8
            .decode(prefix.take(96).toList(), allowMalformed: true)
            .replaceFirst('\uFEFF', '')
            .trimLeft();
        if (head.startsWith('#EXTM3U')) {
          if (prefix.length > 2 * 1024 * 1024) {
            throw const RelayRecordingException(
                RelayStopReason.unsupportedStream);
          }
          while (await iterator.moveNext()) {
            prefix.addAll(iterator.current);
            if (prefix.length > 2 * 1024 * 1024) {
              throw const RelayRecordingException(
                  RelayStopReason.unsupportedStream);
            }
          }
          await iterator.cancel();
          return _Probe.playlist(utf8.decode(prefix, allowMalformed: true));
        }
        if (prefix.length >= 3 * 188) return _Probe.transport(iterator, prefix);
        if (head.startsWith('<') || head.startsWith('{')) {
          throw const RelayRecordingException(
              RelayStopReason.unsupportedStream);
        }
      }
      throw const RelayRecordingException(RelayStopReason.unsupportedStream);
    } catch (_) {
      await iterator.cancel();
      rethrow;
    }
  }

  Future<void> _consumeTs(_RelaySession session,
      StreamIterator<List<int>> iterator, List<int> initial) async {
    final _TsPackets packets = _TsPackets();
    try {
      await _fanout(session, packets.add(initial));
      while (!session.closed && await iterator.moveNext()) {
        await _fanout(session, packets.add(iterator.current));
      }
    } finally {
      await iterator.cancel();
    }
  }

  Future<void> _fanout(_RelaySession session, List<int> bytes) async {
    if (session.closed || bytes.isEmpty) return;
    // Les lecteurs qui s'ajoutent pendant l'écriture reçoivent cette tranche
    // via recent. Le snapshot évite de leur donner deux fois les mêmes octets.
    final List<_PlayerConsumer> players =
        List<_PlayerConsumer>.of(session.players);
    session.recent.add(bytes);
    session.recentBytes += bytes.length;
    while (session.recentBytes > 512 * 1024 && session.recent.length > 1) {
      session.recentBytes -= session.recent.removeFirst().length;
    }
    session.mediaBytes += bytes.length;
    final _RelayRecording? recording = session.recording;
    if (recording != null && !recording.closing) {
      try {
        await recording.append(bytes);
        if (!recording.closing && !recording.started.isCompleted) {
          recording.started.complete();
        }
      } catch (_) {
        await _finishRecording(session, RelayStopReason.diskError);
      }
    }
    for (final _PlayerConsumer consumer in players) {
      if (consumer.done.isCompleted) continue;
      try {
        consumer.response.add(bytes);
      } catch (_) {
        consumer.close();
      }
    }
    if (!session.hasConsumers) _cancelSession(session);
  }

  Future<({String body, Uri uri})> _playlist(
      _RelaySession session, Uri uri) async {
    final _Fetched fetched = await _get(session, uri);
    final _Probe probe = await _probe(fetched);
    if (probe.playlist == null) {
      await probe.iterator?.cancel();
      throw const RelayRecordingException(RelayStopReason.unsupportedStream);
    }
    return (body: probe.playlist!, uri: fetched.uri);
  }

  Future<({String body, Uri uri})> _selectMedia(
      _RelaySession session, String body, Uri uri,
      [int depth = 0]) async {
    if (depth > 3) {
      throw const RelayRecordingException(RelayStopReason.unsupportedStream);
    }
    if (!body.contains('#EXT-X-STREAM-INF:')) {
      _media(body, uri); // refus avant la première écriture
      return (body: body, uri: uri);
    }
    final List<({int bandwidth, Uri uri})> variants = _variants(body, uri);
    for (final variant in variants) {
      try {
        final child = await _playlist(session, variant.uri);
        return await _selectMedia(session, child.body, child.uri, depth + 1);
      } on RelayRecordingException catch (error) {
        if (error.reason != RelayStopReason.unsupportedStream) rethrow;
        // On peut choisir la variante compatible suivante, pas réécrire un
        // conteneur chiffré/fMP4 en faux fichier MPEG-TS.
      }
    }
    throw const RelayRecordingException(RelayStopReason.unsupportedStream);
  }

  Future<void> _hls(_RelaySession session, String first, Uri initialUri) async {
    final selected = await _selectMedia(session, first, initialUri);
    String body = selected.body;
    Uri uri = selected.uri;
    final LinkedHashSet<String> seen = LinkedHashSet<String>();
    while (!session.closed && session.hasConsumers) {
      final _HlsMedia media = _media(body, uri);
      for (final segment in media.segments) {
        if (session.closed) return;
        if (seen.contains(segment.id)) continue;
        try {
          final _Probe content = await _probe(await _get(session, segment.uri));
          if (content.playlist != null) {
            throw const RelayRecordingException(
                RelayStopReason.unsupportedStream);
          }
          await _consumeTs(session, content.iterator!, content.prefix);
        } on RelayRecordingException {
          rethrow;
        } catch (_) {
          // Une erreur au milieu d'un segment ne doit pas recopier son début
          // une deuxième fois en prétendant que l'enregistrement est complet.
          throw const RelayRecordingException(RelayStopReason.networkError);
        }
        seen.add(segment.id);
        while (seen.length > 512) {
          seen.remove(seen.first);
        }
      }
      if (media.ended) return;
      await _wait(session, _playlistPollDelay ?? media.pollDelay);
      if (session.closed) return;
      final refreshed = await _playlist(session, uri);
      body = refreshed.body;
      uri = refreshed.uri;
    }
  }

  List<({int bandwidth, Uri uri})> _variants(String body, Uri base) {
    final List<String> lines =
        body.split('\n').map((String line) => line.trim()).toList();
    final Set<String> externalAudio = <String>{};
    for (final String line in lines) {
      if (line.startsWith('#EXT-X-SESSION-KEY:') &&
          !line.contains('METHOD=NONE')) {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final Map<String, String> attributes = _attributes(line);
        if (attributes['TYPE'] == 'AUDIO' && attributes.containsKey('URI')) {
          externalAudio.add(attributes['GROUP-ID'] ?? '');
        }
      }
    }
    final List<({int bandwidth, Uri uri})> variants =
        <({int bandwidth, Uri uri})>[];
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
      final Map<String, String> attributes = _attributes(lines[i]);
      if (externalAudio.contains(attributes['AUDIO'])) continue;
      final String? codecs = attributes['CODECS'];
      if (codecs != null &&
          codecs.split(',').any((String codec) => !<String>{
                'avc1',
                'avc3',
                'hvc1',
                'hev1',
                'mp4a',
                'ac-3',
                'ec-3',
                'mp2v',
                'mp3'
              }.contains(codec.trim().toLowerCase().split('.').first))) {
        continue;
      }
      for (int j = i + 1; j < lines.length; j++) {
        if (lines[j].isEmpty) continue;
        if (lines[j].startsWith('#')) break;
        variants.add((
          bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
          uri: _httpUri(base.resolve(lines[j]).toString())
        ));
        break;
      }
    }
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return variants;
  }

  _HlsMedia _media(String body, Uri base) {
    if (!body.replaceFirst('\uFEFF', '').trimLeft().startsWith('#EXTM3U')) {
      throw const RelayRecordingException(RelayStopReason.unsupportedStream);
    }
    final List<String> lines =
        body.split('\n').map((String line) => line.trim()).toList();
    int? sequence;
    int target = 6;
    for (final String line in lines) {
      if (line.startsWith('#EXT-X-KEY:') &&
          _attributes(line)['METHOD'] != 'NONE') {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
      if (line.startsWith('#EXT-X-MAP:') ||
          line.startsWith('#EXT-X-BYTERANGE:') ||
          line.startsWith('#EXT-X-I-FRAMES-ONLY') ||
          line.startsWith('#EXT-X-PART:')) {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.split(':').last);
      }
      if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        target = int.tryParse(line.split(':').last) ?? 6;
      }
    }
    final List<({String id, Uri uri})> segments = <({String id, Uri uri})>[];
    bool durationSeen = false;
    for (final String line in lines) {
      if (line.startsWith('#EXTINF:')) durationSeen = true;
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!durationSeen) {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
      final Uri uri = _httpUri(base.resolve(line).toString());
      segments.add((
        id: sequence == null
            ? uri.toString()
            : 'seq:${sequence + segments.length}',
        uri: uri
      ));
      durationSeen = false;
    }
    return _HlsMedia(segments, lines.contains('#EXT-X-ENDLIST'),
        Duration(milliseconds: (target * 500).clamp(500, 5000)));
  }

  Map<String, String> _attributes(String line) {
    final Map<String, String> out = <String, String>{};
    for (final RegExpMatch match
        in RegExp(r'([A-Z0-9-]+)=(?:"([^"]*)"|([^,]*))')
            .allMatches(line.substring(line.indexOf(':') + 1))) {
      out[match[1]!] = match[2] ?? match[3] ?? '';
    }
    return out;
  }

  Future<void> _wait(_RelaySession session, Duration duration) =>
      Future.any<void>(<Future<void>>[
        Future<void>.delayed(duration),
        session.cancelled.future
      ]);

  void _cancelSession(_RelaySession session) {
    if (session.closed) return;
    session.closed = true;
    if (!session.cancelled.isCompleted) session.cancelled.complete();
    session.client?.close(force: true);
    for (final _PlayerConsumer player
        in List<_PlayerConsumer>.of(session.players)) {
      player.close();
    }
    session.players.clear();
  }

  Future<RelayRecordingResult?> _finishRecording(
      _RelaySession session, RelayStopReason reason) async {
    final _RelayRecording? recording = session.recording;
    if (recording == null) return session.lastResult;
    final RelayRecordingResult result = await recording.finish(reason);
    if (identical(session.recording, recording)) {
      session.recording = null;
      session.lastResult = result;
      _finished[session.url] = result;
      while (_finished.length > 16) {
        _finished.remove(_finished.keys.first);
      }
      if (!recording.explicitStop &&
          result.reason != RelayStopReason.userStopped &&
          result.reason != RelayStopReason.cancelled) {
        try {
          recording.onStopped?.call(result);
        } catch (_) {
          // Une vue déjà quittée ne doit pas empêcher la fermeture du fichier.
        }
      }
    }
    return result;
  }
}

Uri _httpUri(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null ||
      !<String>{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const RelayRecordingException(RelayStopReason.unsupportedStream);
  }
  return uri;
}

class _Fetched {
  const _Fetched(this.response, this.uri);
  final HttpClientResponse response;
  final Uri uri;
}

class _Probe {
  const _Probe.playlist(this.playlist)
      : iterator = null,
        prefix = const <int>[];
  const _Probe.transport(this.iterator, this.prefix) : playlist = null;
  final String? playlist;
  final StreamIterator<List<int>>? iterator;
  final List<int> prefix;
}

class _HlsMedia {
  const _HlsMedia(this.segments, this.ended, this.pollDelay);
  final List<({String id, Uri uri})> segments;
  final bool ended;
  final Duration pollDelay;
}

/// Contrôle le conteneur réellement reçu, indépendamment de son URL/MIME.
/// Les premiers paquets doivent présenter trois octets de synchronisation à
/// 188 octets d'intervalle. Aucun HTML, JSON ou texte M3U n'est écrit en vidéo.
class _TsPackets {
  final List<int> _pending = <int>[];
  bool _aligned = false;
  List<int> add(List<int> bytes) {
    _pending.addAll(bytes);
    if (!_aligned) {
      if (_pending.length < 3 * 188) return const <int>[];
      int offset = -1;
      for (int i = 0; i < 188 && i + 376 < _pending.length; i++) {
        if (_pending[i] == 0x47 &&
            _pending[i + 188] == 0x47 &&
            _pending[i + 376] == 0x47) {
          offset = i;
          break;
        }
      }
      if (offset < 0) {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
      if (offset > 0) _pending.removeRange(0, offset);
      _aligned = true;
    }
    final int length = _pending.length ~/ 188 * 188;
    for (int i = 0; i < length; i += 188) {
      if (_pending[i] != 0x47) {
        throw const RelayRecordingException(RelayStopReason.unsupportedStream);
      }
    }
    final List<int> complete = _pending.sublist(0, length);
    _pending.removeRange(0, length);
    return complete;
  }
}

class _RelaySession {
  _RelaySession(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
  final Completer<void> cancelled = Completer<void>();
  final List<_PlayerConsumer> players = <_PlayerConsumer>[];
  final Queue<List<int>> recent = Queue<List<int>>();
  int recentBytes = 0;
  int mediaBytes = 0;
  bool closed = false;
  HttpClient? client;
  Future<void>? pump;
  _RelayRecording? recording;
  RelayRecordingResult? lastResult;
  bool get hasConsumers => players.isNotEmpty || recording?.closing == false;
}

class _PlayerConsumer {
  _PlayerConsumer(this.response);
  final HttpResponse response;
  final Completer<void> done = Completer<void>();
  void close() {
    if (done.isCompleted) return;
    done.complete();
    unawaited(response
        .close()
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}

class _RelayRecording {
  _RelayRecording(this.filePath, this.file, this.onStopped);
  final String filePath;
  final RandomAccessFile file;
  final void Function(RelayRecordingResult)? onStopped;
  final Completer<void> started = Completer<void>();
  Future<void> _writes = Future<void>.value();
  Future<RelayRecordingResult>? _finish;
  int bytes = 0;
  bool closing = false;
  bool explicitStop = false;

  Future<void> append(List<int> chunk) {
    if (closing) return Future<void>.value();
    return _writes = _writes.then((_) async {
      await file.writeFrom(chunk);
      bytes += chunk.length;
    });
  }

  Future<RelayRecordingResult> finish(RelayStopReason reason) =>
      _finish ??= _close(reason);
  Future<RelayRecordingResult> _close(RelayStopReason reason) async {
    closing = true;
    RelayStopReason finalReason = reason;
    try {
      await _writes;
      await file.flush();
    } catch (_) {
      finalReason = RelayStopReason.diskError;
    } finally {
      try {
        await file.close();
      } catch (_) {
        finalReason = RelayStopReason.diskError;
      }
    }
    int actualBytes = 0;
    try {
      actualBytes = await File(filePath).length();
    } catch (_) {
      finalReason = RelayStopReason.diskError;
    }
    if (!started.isCompleted) {
      started.completeError(RelayRecordingException(
          finalReason == RelayStopReason.userStopped
              ? RelayStopReason.cancelled
              : finalReason));
    }
    return RelayRecordingResult(
        filePath: filePath, bytes: actualBytes, reason: finalReason);
  }
}
