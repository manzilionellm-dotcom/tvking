import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/novatube_max_channel_guide.dart';
import 'package:tv_king/features/epg/domain/replay_choice.dart';

void main() {
  test('Grille Xtream réelle de forme, archive par émission et titres en clair ou base64', () {
    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch ~/ 1000;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'epg_listings': [
      {'start_timestamp': stamp - 7200, 'stop_timestamp': stamp - 3600,
       'title': base64Encode(utf8.encode('Émission terminée')), 'has_archive': 1},
      {'start_timestamp': '${stamp - 3600}', 'end_timestamp': '$stamp',
       'title': 'Sans replay', 'has_archive': '0'},
      {'start_timestamp': stamp + 3600, 'stop_timestamp': stamp + 7200,
       'title': 'À venir', 'has_archive': 0},
      {'title': 'Date manquante'},
    ]})));
    final programs = parseMaxChannelGuide((channelId:'xtream-55', bytes:bytes));
    expect(programs.map((p) => p.title), ['Émission terminée', 'Sans replay', 'À venir']);
    const channel = Channel(id:'xtream-55', name:'test', category:'test',
        streamUrl:'https://example.invalid/live/u/p/55.ts', isLive:true,
        catchupSupported:true, catchupDays:2);
    expect(ReplayChoice.urlFor(channel, programs[0], now), contains('/timeshift/'));
    expect(ReplayChoice.urlFor(channel, programs[1], now), isNull);
    expect(ReplayChoice.urlFor(channel, programs[2], now), isNull);
  });
}
