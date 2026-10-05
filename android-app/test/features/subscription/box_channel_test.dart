// Signaux du canal panel → box. Pas de réseau, pas de secret.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/domain/box_channel.dart';

void main() {
  test('un signal de liste est lu, un secret est rejeté', () {
    final BoxChannelFrame? ok = parseBoxChannelFrame(
      '{"v":1,"seq":4,"type":"source","mac":"MK:AA:BB:CC:DD:EE","at":10}',
    );
    expect(ok?.seq, 4);
    expect(ok?.type, 'source');
    expect(channelRefreshesSources('source'), isTrue);
    expect(channelRefreshesSources('source_clear'), isTrue);
    expect(channelRefreshesSources('activate'), isFalse);

    expect(parseBoxChannelFrame('pas du json'), isNull);
    expect(
      parseBoxChannelFrame(
        '{"v":1,"seq":1,"type":"source","mac":"MK:AA:BB:CC:DD:EE","password":"x"}',
      ),
      isNull,
    );
    expect(
      parseBoxChannelFrame(
        '{"v":1,"seq":1,"type":"source","mac":"MK:AA:BB:CC:DD:EE","m3u_url":"secret"}',
      ),
      isNull,
    );
    expect(parseBoxChannelFrame('{"v":1,"type":"hello"}'), isNull);
    expect(
      parseBoxChannelFrame('{"v":1,"seq":1,"type":"source","mac":"AA:BB"}'),
      isNull,
    );
  });

  test('l\'adresse est wss, sans secret dans la query', () {
    final Uri uri = boxChannelUri(
      'https://app.example.test',
      'MK:AA:BB:CC:DD:EE',
    );
    expect(uri.scheme, 'wss');
    expect(uri.path, '/api/box/ws');
    expect(uri.queryParameters['mac'], 'MK:AA:BB:CC:DD:EE');
    expect(uri.query.contains('password'), isFalse);
    expect(
      boxChannelUri('http://127.0.0.1:8787', 'MK:AA:BB:CC:DD:EE').scheme,
      'ws',
    );
  });
}
