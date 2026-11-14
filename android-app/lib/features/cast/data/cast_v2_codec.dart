// Codec protobuf CastMessage v2 minimal, sans plugin natif.
import 'dart:convert';
import 'dart:typed_data';

class CastV2Message {
  const CastV2Message(
      {required this.namespace,
      required this.payload,
      this.sourceId = 'sender-0',
      this.destinationId = 'receiver-0'});
  final String sourceId;
  final String destinationId;
  final String namespace;
  final Map<String, dynamic> payload;

  Uint8List encodeFrame() {
    final List<int> bytes = <int>[8, 0]; // protocol_version = CASTV2_1_0
    void text(int field, String value) {
      final List<int> encoded = utf8.encode(value);
      bytes.add(field << 3 | 2);
      int length = encoded.length;
      while (length >= 128) {
        bytes.add((length & 127) | 128);
        length >>= 7;
      }
      bytes.add(length);
      bytes.addAll(encoded);
    }

    text(2, sourceId);
    text(3, destinationId);
    text(4, namespace);
    bytes.addAll(<int>[40, 0]); // payload_type = STRING
    text(6, jsonEncode(payload));
    final Uint8List frame = Uint8List(bytes.length + 4);
    ByteData.sublistView(frame).setUint32(0, bytes.length);
    frame.setRange(4, frame.length, bytes);
    return frame;
  }

  static CastV2Message decode(List<int> bytes) {
    int offset = 0;
    int varint() {
      int value = 0;
      for (int shift = 0; shift < 64; shift += 7) {
        if (offset >= bytes.length) {
          throw const FormatException('Truncated varint');
        }
        final int byte = bytes[offset++];
        value |= (byte & 127) << shift;
        if (byte < 128) return value;
      }
      throw const FormatException('Invalid varint');
    }

    final Map<int, String> strings = <int, String>{};
    int? version;
    int? payloadType;
    while (offset < bytes.length) {
      final int tag = varint();
      final int field = tag >> 3;
      if (field == 0) throw const FormatException('Invalid protobuf field');
      switch (tag & 7) {
        case 0:
          final int value = varint();
          if (field == 1) version = value;
          if (field == 5) payloadType = value;
        case 2:
          final int length = varint();
          if (length < 0 || offset + length > bytes.length) {
            throw const FormatException('Truncated protobuf field');
          }
          if (<int>{2, 3, 4, 6}.contains(field)) {
            strings[field] =
                utf8.decode(bytes.sublist(offset, offset + length));
          }
          offset += length;
        case 1:
          offset += 8;
        case 5:
          offset += 4;
        default:
          throw const FormatException('Unsupported protobuf wire type');
      }
      if (offset > bytes.length) {
        throw const FormatException('Truncated protobuf');
      }
    }
    if (version != 0 ||
        payloadType != 0 ||
        !<int>[2, 3, 4, 6].every(strings.containsKey)) {
      throw const FormatException('Not a Cast v2 JSON message');
    }
    final Object? payload = jsonDecode(strings[6]!);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid Cast JSON');
    }
    return CastV2Message(
        namespace: strings[4]!,
        payload: payload,
        sourceId: strings[2]!,
        destinationId: strings[3]!);
  }
}

/// TCP/TLS peut fragmenter une trame ou en regrouper plusieurs.
class CastV2FrameDecoder {
  static const int maxFrameSize = 1024 * 1024;
  final List<int> _buffer = <int>[];
  List<CastV2Message> add(List<int> chunk) {
    // Décoder toutes les trames complètes, ne garder que la fin incomplète.
    _buffer.addAll(chunk);
    final List<CastV2Message> messages = <CastV2Message>[];
    while (_buffer.length >= 4) {
      final int size = (_buffer[0] << 24) |
          (_buffer[1] << 16) |
          (_buffer[2] << 8) |
          _buffer[3];
      if (size <= 0 || size > maxFrameSize) {
        _buffer.clear();
        throw const FormatException('Invalid Cast frame length');
      }
      if (_buffer.length < size + 4) break;
      final List<int> body = _buffer.sublist(4, size + 4);
      _buffer.removeRange(0, size + 4);
      messages.add(CastV2Message.decode(body));
    }
    return messages;
  }
}

abstract final class CastV2Commands {
  static const String connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const String heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const String receiver = 'urn:x-cast:com.google.cast.receiver';
  static const String media = 'urn:x-cast:com.google.cast.media';
  static const String defaultReceiver = 'CC1AD845';

  static Map<String, dynamic> load(
          {required int requestId,
          required String url,
          required String contentType,
          required String title,
          String? imageUrl,
          bool live = true}) =>
      <String, dynamic>{
        'type': 'LOAD',
        'requestId': requestId,
        'autoplay': true,
        'media': <String, dynamic>{
          'contentId': url,
          'contentType': contentType,
          'streamType': live ? 'LIVE' : 'BUFFERED',
          'metadata': <String, dynamic>{
            'metadataType': 0,
            'title': title,
            if (imageUrl != null)
              'images': <Object>[
                <String, String>{'url': imageUrl}
              ]
          }
        }
      };
}

/// Le probe peut annoncer octet-stream/text/plain : l'extension et les MIME
/// adaptatifs priment. Aucun transcodage : le récepteur décide des codecs.
String castV2ContentType(String url, String? probedMime) {
  final String path = Uri.parse(url).path.toLowerCase();
  final String mime = (probedMime ?? '').split(';').first.trim().toLowerCase();
  if (path.endsWith('.m3u8') || mime.contains('mpegurl')) {
    return 'application/x-mpegURL';
  }
  if (path.endsWith('.mpd') || mime == 'application/dash+xml') {
    return 'application/dash+xml';
  }
  if (path.endsWith('.mp4')) return 'video/mp4';
  if (path.endsWith('.mkv')) return 'video/x-matroska';
  if (path.endsWith('.ts')) return 'video/mp2t';
  if (mime.startsWith('video/') || mime.startsWith('audio/')) return mime;
  return 'video/mp2t';
}
