import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/desktop/desktop_image_settings.dart';
import 'package:tv_king/features/tv/desktop/desktop_playback_queue.dart';

void main() {
  test('le moteur sélectionné est appliqué avant la première URL', () async {
    final queue = DesktopPlaybackQueue();
    final settings = DesktopImageSettings();
    final initialized = Completer<void>();
    final properties = <String, String>{};
    final events = <String>[];
    final init = queue.configure(() async {
      await initialized.future;
      events.add('initialisé');
    });
    final decoder = queue.configure(() async {
      await settings.apply('software',
          setProperty: (key, value) async {
            properties[key] = value;
          },
          getProperty: (key) async => properties[key] ?? '');
      events.add('décodeur');
    });
    final opening = queue.replace(() async {
      expect(properties['hwdec'], 'no');
      events.add('URL');
    });
    expect(events, isEmpty);
    initialized.complete();
    await Future.wait([init, decoder, opening]);
    expect(events, ['initialisé', 'décodeur', 'URL']);
    expect(settings.capabilities['name'], 'software');
  });

  test('un zap remplacé pendant ses préparatifs n’ouvre pas son URL', () async {
    final queue = DesktopPlaybackQueue();
    final preparing = Completer<void>();
    final ready = Completer<void>();
    final opened = <String>[];
    final obsolete = queue.replace(() async {
      opened.add('ancienne');
    }, prepare: () async {
      preparing.complete();
      await ready.future;
    });
    await preparing.future;
    final latest = queue.replace(() async {
      opened.add('dernière');
    });
    ready.complete();
    await Future.wait([obsolete, latest]);
    expect(opened, ['dernière']);
  });

  test('un arrêt pendant les préparatifs annule aussi leur erreur tardive',
      () async {
    final queue = DesktopPlaybackQueue();
    final preparing = Completer<void>();
    final ready = Completer<void>();
    final events = <String>[];
    final opening = queue.replace(() async {
      events.add('URL');
    }, prepare: () async {
      preparing.complete();
      await ready.future;
      throw StateError('ancienne préparation');
    });
    await preparing.future;
    final stop = queue.stop(() async {
      events.add('stop');
    });
    ready.complete();
    await Future.wait([opening, stop]);
    expect(events, ['stop']);
  });

  test('fermer pendant la préparation empêche URL et réglage tardifs',
      () async {
    final queue = DesktopPlaybackQueue();
    final preparing = Completer<void>();
    final ready = Completer<void>();
    final events = <String>[];
    final opening = queue.replace(() async {
      events.add('URL');
    }, prepare: () async {
      preparing.complete();
      await ready.future;
    });
    await preparing.future;
    final closing = queue.close(() async {
      events.add('dispose');
    });
    final late = queue.configure(() async {
      events.add('réglage');
    });
    ready.complete();
    await Future.wait([opening, closing, late]);
    expect(events, ['dispose']);
  });

  test('une erreur de préparation active remonte sans bloquer le prochain zap',
      () async {
    final queue = DesktopPlaybackQueue();
    final opened = <String>[];
    await expectLater(
      queue.replace(() async {
        opened.add('invalide');
      }, prepare: () async => throw StateError('préparation impossible')),
      throwsStateError,
    );
    await queue.replace(() async {
      opened.add('valide');
    });
    expect(opened, ['valide']);
  });

  test('matériel autorise le GPU ; FFmpeg hérité utilise le logiciel du PC',
      () async {
    final settings = DesktopImageSettings();
    final properties = <String, String>{};
    Future<void> select(String engine) => settings.apply(engine,
        setProperty: (key, value) async => properties[key] = value,
        getProperty: (key) async => properties[key] ?? '');
    await select('hardware');
    expect(properties['hwdec'], 'auto');
    await select('ffmpeg');
    expect(properties['hwdec'], 'no');
    expect(settings.capabilities['name'], 'software');
    expect(settings.capabilities['ffmpegVideo'], isFalse);
    await select('hardware');
    expect(properties['hwdec'], 'auto');
    expect(settings.capabilities['name'], 'hardware');
  });

  test('une propriété ignorée par libmpv ne confirme pas un faux moteur',
      () async {
    final settings = DesktopImageSettings();
    await settings.apply('software',
        setProperty: (_, __) async {}, getProperty: (_) async => 'no');
    await expectLater(
      settings.apply('hardware',
          setProperty: (_, __) async {}, getProperty: (_) async => 'no'),
      throwsStateError,
    );
    expect(settings.capabilities['name'], 'software');
  });
}
