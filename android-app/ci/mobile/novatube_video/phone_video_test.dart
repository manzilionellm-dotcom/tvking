import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:novatube_video/novatube_video.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('novatube_video/4');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> commands;
  late PhoneVideoPlayer player;
  Media media(String name) => Media('https://example.invalid/$name');
  Future<void> event(String method, dynamic data) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, data)),
      (_) {},
    );
  }

  setUp(() {
    commands = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      commands.add(call);
      return null;
    });
    player = PhoneVideoPlayer(vod: false, userAgent: () => 'Mobile');
  });
  tearDown(() async {
    await player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'deux zaps avant la surface ouvrent seulement la dernière chaîne',
    () async {
      await player.open(media('a'));
      await player.open(media('b'));
      await player.attach(4);
      final opens = commands.where((c) => c.method == 'setUrl');
      expect(opens.length, 1);
      expect(opens.single.arguments['url'], endsWith('/b'));
      expect(opens.single.arguments['headers']['User-Agent'], 'Mobile');
      await event('ack', 1);
      await event('firstFrame', null);
      expect(player.firstFrame, isFalse);
      await event('ack', 2);
      await event('videoSize', {'width': 1920, 'height': 1080});
      expect(player.state.width, isNull);
      await event('firstFrame', null);
      expect(player.state.width, 1920);
    },
  );
  test('l’arrêt avant attachement annule le flux et ses callbacks', () async {
    await player.open(media('a'));
    await player.stop();
    await player.attach(4);
    expect(commands.any((c) => c.method == 'setUrl'), isFalse);
    await event('ack', 1);
    await event('playing', true);
    expect(player.state.playing, isFalse);
  });
  test(
    'reprise native, pistes et pause gardent les commandes du téléphone',
    () async {
      await player.attach(4);
      player.forceHls();
      await player.open(media('hls'), play: false);
      await event('ack', 1);
      expect(commands.last.method, 'pause');
      expect(
        commands.firstWhere((c) => c.method == 'setUrl').arguments['mime'],
        'application/x-mpegURL',
      );
      await event('reconnecting', true);
      expect(player.recovering, isTrue);
      await event('firstFrame', null);
      expect(player.recovering, isFalse);
      await event('tracks', [
        {
          'type': 'audio',
          'group': 0,
          'index': 1,
          'language': 'fr',
          'selected': true,
        },
      ]);
      expect(player.audioWithoutVideo, isTrue);
      await player.setAudioTrack(player.state.track.audio);
      expect(commands.last.arguments, {'group': 0, 'index': 1});
      await player.setSubtitleTrack(SubtitleTrack.no());
      expect(commands.last.arguments, {'type': 'text', 'disable': true});
    },
  );
}
