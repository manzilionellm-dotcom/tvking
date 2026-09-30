import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/image_engine.dart';
import 'package:tv_king/features/player/domain/live_bar_slots.dart';

void main() {
  test('moteur inconnu = matériel, le réglage d\'origine', () {
    expect(ImageEngine.fromWire(null), ImageEngine.hardware);
    expect(ImageEngine.fromWire('vlc'), ImageEngine.hardware);
    expect(ImageEngine.fromWire('software').wire, 'software');
  });

  test('le bouton avance matériel → logiciel → ffmpeg s\'il est là', () {
    expect(
      EngineStep.next(ImageEngine.hardware, ffmpegVideo: true).engine,
      ImageEngine.software,
    );
    final EngineStep toFfmpeg =
        EngineStep.next(ImageEngine.software, ffmpegVideo: true);
    expect(toFfmpeg.engine, ImageEngine.ffmpeg);
    expect(toFfmpeg.ffmpegMissing, isFalse);
    expect(
      EngineStep.next(ImageEngine.ffmpeg, ffmpegVideo: true).engine,
      ImageEngine.hardware,
    );
  });

  test('sans FFmpeg vidéo on le dit et on revient au matériel', () {
    final EngineStep step =
        EngineStep.next(ImageEngine.software, ffmpegVideo: false);
    expect(step.engine, ImageEngine.hardware);
    expect(step.ffmpegMissing, isTrue);
  });

  test('le contraste demandé ne s\'applique pas si le matériel refuse', () {
    expect(
      PictureTuneChoice.resolve(requested: true, hardwareAllows: false),
      isFalse,
    );
    expect(
      PictureTuneChoice.resolve(requested: true, hardwareAllows: true),
      isTrue,
    );
  });

  test('le bouton moteur est après Guide, REC, Favori, et après les autres', () {
    expect(LiveBarSlots.start(false), isNull);
    expect(LiveBarSlots.start(true), 3);
    expect(LiveBarSlots.subs(showStart: false, showSubs: false), isNull);
    expect(LiveBarSlots.subs(showStart: false, showSubs: true), 3);
    expect(LiveBarSlots.subs(showStart: true, showSubs: true), 4);
    expect(LiveBarSlots.engine(showStart: false, showSubs: false), 3);
    expect(LiveBarSlots.engine(showStart: true, showSubs: true), 5);
    expect(LiveBarSlots.count(showStart: false, showSubs: false), 4);
    expect(LiveBarSlots.count(showStart: true, showSubs: true), 6);
    // « Suivre » s'insère après Favori et décale le reste, pas Guide/REC/Favori.
    expect(LiveBarSlots.follow(false), isNull);
    expect(LiveBarSlots.follow(true), 3);
    expect(LiveBarSlots.start(true, showFollow: true), 4);
    expect(
      LiveBarSlots.engine(showStart: true, showSubs: true, showFollow: true),
      6,
    );
    expect(
      LiveBarSlots.count(showStart: true, showSubs: true, showFollow: true),
      7,
    );
  });
}
