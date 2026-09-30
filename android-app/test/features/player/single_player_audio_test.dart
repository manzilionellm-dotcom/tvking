// =========================================================
//  single_player_audio_test.dart — deux controllers, une voix
// =========================================================
//  Le moteur est un faux (pas d'ExoPlayer). On vérifie que le
//  second zap coupe le premier, et que la piste choisie est la
//  voix, pas le commentaire.
// =========================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:native_video_player/playback_lease.dart';

class _FakeBackend implements NativeVideoBackend {
  int silences = 0;
  int opens = 0;
  NativeTrack? picked;

  @override
  void bind(NativeVideoController controller) {}

  @override
  void open(Map<String, dynamic> args) {
    opens++;
  }

  @override
  void play() {}

  @override
  void pause() {}

  @override
  void seekTo(Duration position) {}

  @override
  void selectTrack(NativeTrack track) {
    picked = track;
  }

  @override
  void disableSubtitles() {}

  @override
  void silence() {
    silences++;
  }

  @override
  void setClearVoice(bool enabled) {}

  @override
  Widget buildView(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {}
}

void main() {
  final List<_FakeBackend> made = <_FakeBackend>[];

  setUp(() {
    made.clear();
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
    NativeVideoController.appAudioLanguage = 'fr';
    NativeVideoController.backendFactory = () {
      final _FakeBackend backend = _FakeBackend();
      made.add(backend);
      return backend;
    };
  });

  tearDown(() {
    NativeVideoController.backendFactory = null;
    NativeVideoController.appAudioLanguage = null;
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
  });

  test('le second lecteur coupe le premier avant de parler', () {
    final NativeVideoController first = NativeVideoController();
    final NativeVideoController second = NativeVideoController();
    first.setUrl('http://a.example.invalid/1.ts');
    expect(first.audible, isTrue);
    expect(made[0].opens, 1);
    second.setUrl('http://a.example.invalid/2.ts');
    expect(second.audible, isTrue);
    expect(first.audible, isFalse);
    expect(made[0].silences, 1);
    expect(made[1].opens, 1);
    expect(NativeVideoController.audiblePlayers.owner, isNotNull);
    first.dispose();
    second.dispose();
  });

  test('vingt zaps entre deux lecteurs : un seul reste audible', () {
    final NativeVideoController left = NativeVideoController();
    final NativeVideoController right = NativeVideoController();
    final Stopwatch watch = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      final NativeVideoController who = i.isEven ? left : right;
      who.setUrl('http://a.example.invalid/$i.ts');
    }
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(500));
    final int audible = (left.audible ? 1 : 0) + (right.audible ? 1 : 0);
    expect(audible, 1);
    expect(right.audible, isTrue);
    expect(left.audible, isFalse);
    expect(made[0].silences, greaterThan(0));
    left.dispose();
    right.dispose();
  });

  test('la première liste de pistes choisit le français, pas le commentaire', () {
    final NativeVideoController player = NativeVideoController();
    player.setUrl('http://a.example.invalid/live.ts');
    player.applyBackendEvent('tracks', <Map<String, Object?>>[
      <String, Object?>{
        'type': 'audio',
        'group': 0,
        'index': 0,
        'language': 'en',
        'label': 'Commentary',
        'channels': 2,
        'selected': true,
        'roleFlags': 0,
      },
      <String, Object?>{
        'type': 'audio',
        'group': 0,
        'index': 1,
        'language': 'fre',
        'label': 'VF',
        'channels': 2,
        'selected': false,
        'roleFlags': 0,
      },
    ]);
    expect(made.single.picked?.language, 'fre');
    expect(made.single.picked?.index, 1);
    // Un choix manuel ensuite n'est pas écrasé par une nouvelle liste.
    player.selectTrack(const NativeTrack(
      isAudio: true,
      group: 0,
      index: 0,
      selected: false,
      language: 'en',
      label: 'English',
    ));
    player.applyBackendEvent('tracks', <Map<String, Object?>>[
      <String, Object?>{
        'type': 'audio',
        'group': 0,
        'index': 0,
        'language': 'en',
        'label': 'English',
        'selected': true,
      },
      <String, Object?>{
        'type': 'audio',
        'group': 0,
        'index': 1,
        'language': 'fr',
        'label': 'VF',
        'selected': false,
      },
    ]);
    expect(made.single.picked?.language, 'en');
    player.dispose();
  });
}
