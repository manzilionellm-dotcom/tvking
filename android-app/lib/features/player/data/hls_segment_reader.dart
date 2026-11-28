// Flux HLS avec segments MPEG-TS multiplexés pour le relais lecture + REC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class HlsSegmentReader {
  int? _nextSequence;
  Timer? _timer;
  Completer<void>? _waiting;
  bool _closed = false;
  final _withoutProgress = Stopwatch();

  void close() {
    _closed = true;
    _timer?.cancel();
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> _wait(Duration duration) {
    if (_closed || duration <= Duration.zero) return Future.value();
    final waiting = _waiting = Completer<void>();
    _timer = Timer(duration, () {
      _waiting = null;
      waiting.complete();
    });
    return waiting.future;
  }

  static Uri _resolve(Uri base, String value) {
    final uri = base.resolve(value);
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Adresse HLS non HTTP');
    }
    return uri;
  }

  /// Adresse finale après les redirections HTTP, y compris relatives.
  /// Elle identifie le format et sert de base aux références du manifeste.
  static Uri effectiveUri(Uri base, HttpClientResponse response) =>
      response.redirects
          .fold(base, (uri, redirect) => uri.resolveUri(redirect.location));

  static Future<Uint8List> _bytes(HttpClientResponse response, int limit,
      {bool manifest = false}) async {
    if (response.contentLength > limit) {
      throw const FormatException('Ressource HLS trop grande');
    }
    final data = BytesBuilder(copy: false);
    // Le client conserve les octets TS. Pour les manifestes compressés, la
    // limite porte aussi sur le texte décompressé avant sa lecture en UTF-8.
    final gzipManifest = manifest &&
        response.headers
                .value(HttpHeaders.contentEncodingHeader)
                ?.toLowerCase() ==
            'gzip';
    final body = gzipManifest ? gzip.decoder.bind(response) : response;
    await for (final chunk in body.timeout(const Duration(seconds: 15))) {
      if (data.length + chunk.length > limit) {
        throw const FormatException('Ressource HLS trop grande');
      }
      data.add(chunk);
    }
    return data.takeBytes();
  }

  static Future<HttpClientResponse> _fetch(HttpClient client, Uri uri,
      {String? range}) async {
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 15));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != (range == null ? 200 : 206)) {
      throw HttpException('HTTP ${response.statusCode} en capture HLS');
    }
    return response;
  }

  Stream<Uint8List> read(
      HttpClient client, Uri uri, HttpClientResponse response) async* {
    var depth = 0;
    _withoutProgress
      ..reset()
      ..start();
    while (!_closed) {
      uri = effectiveUri(uri, response);
      final body =
          utf8.decode(await _bytes(response, 1024 * 1024, manifest: true));
      final lines = const LineSplitter()
          .convert(body)
          .map((line) => line.trim())
          .toList();
      if (lines.isEmpty || lines.first != '#EXTM3U') {
        throw const FormatException('Manifeste HLS absent');
      }
      final variants = <({Uri uri, int bandwidth})>[];
      int? bandwidth;
      for (final line in lines) {
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          // Le relais TS écrit une seule piste multiplexée. Ne jamais produire
          // une capture muette lorsqu'une piste audio externe est nécessaire.
          if (RegExp(r'(?:[:,])AUDIO=').hasMatch(line)) {
            bandwidth = null;
            continue;
          }
          bandwidth = int.tryParse(
              RegExp(r'(?:[:,])BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ??
                  '');
        } else if (bandwidth != null &&
            line.isNotEmpty &&
            !line.startsWith('#')) {
          variants.add((uri: _resolve(uri, line), bandwidth: bandwidth));
          bandwidth = null;
        }
      }
      if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF:'))) {
        if (++depth > 3 || variants.isEmpty) {
          throw const FormatException('Variante multiplexée introuvable');
        }
        variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
        uri = variants.last.uri;
        response = await _fetch(client, uri);
        continue;
      }

      var sequence = 0;
      var targetSeconds = 4;
      Duration? duration;
      ({int length, int? offset})? range;
      Uri? previousUri;
      int? previousEnd;
      final segments = <({
        int sequence,
        Uri uri,
        Duration duration,
        int? offset,
        int? length
      })>[];
      for (final line in lines) {
        if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
          sequence = int.parse(line.split(':').last);
          if (sequence < 0) {
            throw const FormatException('Séquence HLS invalide');
          }
        } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
          targetSeconds = int.parse(line.split(':').last);
        } else if (line.startsWith('#EXT-X-KEY:') &&
                !RegExp(r'(?:[:,])METHOD=NONE(?:,|$)').hasMatch(line) ||
            line.startsWith('#EXT-X-MAP:') ||
            line.startsWith('#EXT-X-GAP')) {
          throw const FormatException(
              'Capture TS incompatible avec cette playlist');
        } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
          final m =
              RegExp(r'^#EXT-X-BYTERANGE:(\d+)(?:@(\d+))?$').firstMatch(line);
          if (m == null) throw const FormatException('Plage HLS invalide');
          range = (length: int.parse(m[1]!), offset: int.tryParse(m[2] ?? ''));
        } else if (line.startsWith('#EXTINF:')) {
          final seconds = double.parse(line.substring(8).split(',').first);
          if (!seconds.isFinite || seconds <= 0) {
            throw const FormatException('Durée HLS invalide');
          }
          duration = Duration(microseconds: (seconds * 1000000).round());
        } else if (line.isNotEmpty && !line.startsWith('#')) {
          if (duration == null) {
            throw const FormatException('Durée du segment absente');
          }
          final source = _resolve(uri, line);
          final offset = range == null
              ? null
              : range.offset ?? (source == previousUri ? previousEnd : null);
          if (range != null && (offset == null || range.length <= 0)) {
            throw const FormatException('Plage HLS ambiguë');
          }
          segments.add((
            sequence: sequence++,
            uri: source,
            duration: duration,
            offset: offset,
            length: range?.length
          ));
          previousEnd = offset == null ? null : offset + range!.length;
          previousUri = source;
          duration = null;
          range = null;
        }
      }
      final ended = lines.contains('#EXT-X-ENDLIST');
      if (segments.isNotEmpty) {
        _nextSequence ??= ended
            ? segments.first.sequence
            : segments[math.max(0, segments.length - 3)].sequence;
        if (_nextSequence! < segments.first.sequence) {
          throw const FormatException('Segment sorti de la fenêtre HLS');
        }
      }
      var delivered = false;
      for (final s in segments) {
        if (_closed) return;
        if (s.sequence < _nextSequence!) continue;
        final range = s.offset == null
            ? null
            : 'bytes=${s.offset}-${s.offset! + s.length! - 1}';
        final clock = Stopwatch()..start();
        final media = await _fetch(client, s.uri, range: range);
        if (range != null) {
          final expected = 'bytes ${s.offset}-${s.offset! + s.length! - 1}/';
          if (!(media.headers
                  .value(HttpHeaders.contentRangeHeader)
                  ?.startsWith(expected) ??
              false)) {
            throw const FormatException('Plage HLS différente de la demande');
          }
        }
        final ts = await _bytes(media, 24 * 1024 * 1024);
        if (s.length != null && ts.length != s.length) {
          throw const HttpException('Segment HLS incomplet');
        }
        if (ts.length < 188 ||
            ts.length % 188 != 0 ||
            ts[0] != 0x47 ||
            (ts.length > 188 && ts[188] != 0x47)) {
          throw const FormatException(
              'Le segment reçu ne contient pas de paquets MPEG-TS');
        }
        if (_closed) return;
        delivered = true;
        _nextSequence = s.sequence + 1;
        _withoutProgress.reset();
        yield ts;
        await _wait(s.duration - clock.elapsed);
      }
      if (_closed || ended) return;
      if (_withoutProgress.elapsed.inSeconds >=
          math.max(30, targetSeconds * 3)) {
        throw const HttpException('La playlist HLS ne progresse plus');
      }
      if (!delivered) {
        await _wait(
            Duration(milliseconds: (targetSeconds * 500).clamp(250, 3000)));
      }
      if (_closed) return;
      response = await _fetch(client, uri);
    }
  }
}
