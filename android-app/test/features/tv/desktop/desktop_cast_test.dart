import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/tv/desktop/desktop_playback_queue.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('Windows propose uniquement les transports réseau disponibles', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(CastPlatform.supports(CastDeviceKind.dlna), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.roku), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.chromecast), isFalse);
    expect(CastPlatform.supports(CastDeviceKind.googleCast), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(CastPlatform.supports(CastDeviceKind.googleCast), isTrue);
  });
  test('Stop attend une ouverture en cours puis ferme le flux local', () async {
    final queue = DesktopPlaybackQueue();
    final entered = Completer<void>(); final finish = Completer<void>();
    final events = <String>[];
    final opening = queue.replace(() async { entered.complete(); await finish.future; events.add('open'); });
    await entered.future;
    final stopping = queue.stop(() async { events.add('stop'); });
    finish.complete(); await opening; await stopping;
    expect(events, ['open', 'stop']);
  });
  test('un zap en attente ne rouvre pas le PC après le départ du Cast', () async {
    final queue = DesktopPlaybackQueue(); final blocker = Completer<void>();
    final entered = Completer<void>(); final events = <String>[];
    final first = queue.replace(() async { entered.complete(); await blocker.future; events.add('first'); });
    await entered.future;
    final obsolete = queue.replace(() async { events.add('obsolete'); });
    final stop = queue.stop(() async { events.add('stop'); });
    blocker.complete(); await Future.wait([first, obsolete, stop]);
    expect(events, ['first', 'stop']);
  });
  test('le retour PC fonctionne après une erreur d’ouverture', () async {
    final queue = DesktopPlaybackQueue();
    await expectLater(queue.replace(() async { throw StateError('failed'); }), throwsStateError);
    var resumed = false; await queue.replace(() async { resumed = true; });
    expect(resumed, isTrue);
  });
  test('un lecteur fermé ignore toute ouverture tardive', () async {
    final queue = DesktopPlaybackQueue(); var reopened = false;
    await queue.close(() async {});
    await queue.replace(() async { reopened = true; });
    expect(reopened, isFalse);
  });
}
