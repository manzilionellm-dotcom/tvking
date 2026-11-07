import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_v2_codec.dart';

void main() {
  test('MIME inference respects adaptive playlists and extensionless probe',
      () {
    expect(castV2ContentType('http://example.com/live.m3u8?q=1', 'text/plain'),
        'application/x-mpegURL');
    expect(
        castV2ContentType(
            'http://example.com/live', 'application/vnd.apple.mpegurl'),
        'application/x-mpegURL');
    expect(
        castV2ContentType(
            'http://example.com/live.ts', 'application/octet-stream'),
        'video/mp2t');
    expect(
        castV2ContentType('http://example.com/movie.mp4', null), 'video/mp4');
    expect(castV2ContentType('http://example.com/a.mpd', null),
        'application/dash+xml');
  });

  test('protobuf fields and big-endian framing match wire specification', () {
    const CastV2Message m = CastV2Message(
        namespace: 'n',
        sourceId: 's',
        destinationId: 'd',
        payload: <String, dynamic>{'type': 'PING'});
    final Uint8List f = m.encodeFrame();
    expect(ByteData.sublistView(f).getUint32(0), f.length - 4);
    expect(f.sublist(4), <int>[
      8,
      0,
      18,
      1,
      115,
      26,
      1,
      100,
      34,
      1,
      110,
      40,
      0,
      50,
      15,
      123,
      34,
      116,
      121,
      112,
      101,
      34,
      58,
      34,
      80,
      73,
      78,
      71,
      34,
      125
    ]);
    final CastV2Message d = CastV2Message.decode(f.sublist(4));
    expect(d.sourceId, 's');
    expect(d.destinationId, 'd');
    expect(d.namespace, 'n');
    expect(d.payload, m.payload);
  });
  test('fragmented/coalesced frames and long UTF8 payload', () {
    final Uint8List f = CastV2Message(
        namespace: CastV2Commands.media,
        payload: <String, dynamic>{
          'title': List<String>.filled(150, 'é').join()
        }).encodeFrame();
    final CastV2FrameDecoder d = CastV2FrameDecoder();
    for (final int b in f.sublist(0, f.length - 1)) {
      expect(d.add(<int>[b]), isEmpty);
    }
    expect(d.add(<int>[f.last, ...f]).length, 2);
  });
  test('invalid lengths and truncated varints/fields rejected', () {
    for (final List<int> bytes in <List<int>>[
      <int>[0, 16, 0, 1],
      <int>[0, 0, 0, 0]
    ]) {
      expect(() => CastV2FrameDecoder().add(bytes), throwsFormatException);
    }
    for (final List<int> bytes in <List<int>>[
      <int>[18, 100, 1],
      <int>[128],
      <int>[0, 0]
    ]) {
      expect(() => CastV2Message.decode(bytes), throwsFormatException);
    }
  });
  test('LOAD contains HLS MIME, real URL, metadata, autoplay and request ID',
      () {
    final Map<String, dynamic> m = CastV2Commands.load(
        requestId: 42,
        url: 'http://192.168.1.2/live.m3u8',
        contentType: 'application/x-mpegURL',
        title: 'Test');
    expect(m['requestId'], 42);
    expect(m['autoplay'], true);
    expect(m['media']['contentId'], 'http://192.168.1.2/live.m3u8');
    expect(m['media']['contentType'], 'application/x-mpegURL');
    expect(m['media']['streamType'], 'LIVE');
    expect(CastV2Commands.defaultReceiver, 'CC1AD845');
  });
}
