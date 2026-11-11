import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

Map<String, Object?> _payload(
  int mediaId, {
  int sessionId = 1,
  bool summary = false,
  int? firstFrame = 1250,
  int? dropped,
}) =>
    <String, Object?>{
      'schema': 1,
      'origin': 'android_media3',
      'kind': summary ? 'summary' : 'first_frame',
      'sessionId': sessionId,
      'mediaId': mediaId,
      'startedElapsedMs': 1000,
      'observedElapsedMs': 1600,
      'firstFrameElapsedMs': firstFrame,
      'startupMs': firstFrame == null ? null : firstFrame - 1000,
      'elapsedMs': 600,
      'droppedFrames': dropped,
      'droppedSource': dropped == null ? null : 'decoder',
      'rebufferCount': 0,
      'rebufferMs': 0,
      'liveOffsetMs': null,
      'endReason': summary ? 'disposed' : null,
    };

class _NativeHarness {
  _NativeHarness(this.tester);
  final WidgetTester tester;
  final calls = <MethodCall>[];
  final channels = <MethodChannel>[];
  final reports = <NativePlaybackMetrics>[];
  late NativeVideoController controller;
  Object? disposeSummary;

  Future<void> attach({bool enabled = true}) async {
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.playbackMetricsEnabled = enabled;
    NativeVideoController.onPlaybackMetrics = reports.add;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        final channel = MethodChannel('native_video_player/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'dispose' ? disposeSummary : null;
        });
      }
      return null;
    });
    controller = NativeVideoController(
        initialUrl: 'https://fixture.invalid/metrics-a.ts');
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
      width: 320,
      height: 180,
      child: NativeVideoView(controller: controller),
    )));
    for (var n = 0; n < 5; n++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Map<Object?, Object?> get lastOpen =>
      calls.lastWhere((call) => call.method == 'setUrl').arguments
          as Map<Object?, Object?>;
  int get mediaId => lastOpen['metricsMediaId'] as int;

  Future<void> native(Object? value) async {
    final delivered = Completer<void>();
    // Même entrée que le moteur Android ; aucun appel à applyBackendEvent.
    ServicesBinding.instance.channelBuffers.push(
      channels.single.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('playbackMetrics', value)),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await tester.pump();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    NativeVideoController.playbackMetricsEnabled = false;
    NativeVideoController.onPlaybackMetrics = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opt-in absent : aucune demande de mesure dans le paquet partagé',
      (tester) async {
    expect(NativeVideoController.playbackMetricsEnabled, isFalse);
    final h = _NativeHarness(tester);
    await h.attach(enabled: false);
    try {
      expect(h.lastOpen.containsKey('metricsMediaId'), isFalse);
      await h.native(_payload(1));
      expect(h.reports, isEmpty);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'secours position et événement synthétique ne deviennent pas une preuve native',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      h.controller.applyBackendEvent('ack', 0);
      h.controller.applyBackendEvent('playing', true);
      h.controller.applyBackendEvent('position', 500);
      expect(h.controller.firstFrame, isTrue);
      h.controller.applyBackendEvent('playbackMetrics', _payload(h.mediaId));
      expect(h.reports, isEmpty);
      await h.native(_payload(h.mediaId));
      expect(h.reports.single.firstFrameElapsedMs, 1250);
      expect(h.reports.single.startupMs, 250);
    } finally {
      await h.close();
    }
  });

  testWidgets('une mesure native ne commande ni affichage ni reconstruction',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      var rebuilds = 0;
      h.controller.addListener(() => rebuilds++);
      await h.native(_payload(h.mediaId));
      expect(h.reports, hasLength(1));
      expect(h.controller.firstFrame, isFalse);
      expect(rebuilds, 0);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'première image et bilan sont publiés au plus une fois par session',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      await h.native(_payload(h.mediaId));
      await h.native(_payload(h.mediaId));
      await h.native(_payload(h.mediaId, summary: true));
      await h.native(_payload(h.mediaId, summary: true));
      await h.native(_payload(h.mediaId));
      expect(h.reports, hasLength(2));
      expect(h.reports.last.isSummary, isTrue);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'reconnexion garde le média ; autre sélection invalide sa première image tardive',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      final first = h.mediaId;
      h.controller.setUrl('https://fixture.invalid/metrics-a.ts');
      await tester.pump();
      expect(h.mediaId, first);
      h.controller.setUrl('https://fixture.invalid/metrics-b.ts');
      await tester.pump();
      final next = h.mediaId;
      expect(next, isNot(first));
      await h.native(_payload(first));
      expect(h.reports, isEmpty);
      await h.native(_payload(first, summary: true));
      await h.native(_payload(next, sessionId: 2));
      expect(h.reports.map((m) => m.mediaId), <int>[first, next]);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'ancienne session et média étranger ne remplacent pas la session actuelle',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      await h.native(_payload(h.mediaId, sessionId: 3));
      await h.native(_payload(h.mediaId, sessionId: 2, summary: true));
      await h.native(_payload(h.mediaId + 0x100000000, sessionId: 4));
      await h.native(_payload(h.mediaId + 1, sessionId: 4));
      expect(h.reports, hasLength(1));
      expect(h.reports.single.sessionId, 3);
    } finally {
      await h.close();
    }
  });

  testWidgets('releaseNative reçoit le bilan après retrait du handler',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      h.disposeSummary = _payload(h.mediaId, summary: true);
      await h.controller.releaseNative();
      expect(h.reports.single.isSummary, isTrue);
      await h.controller.releaseNative();
      expect(h.calls.where((c) => c.method == 'dispose'), hasLength(1));
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'dispose synchrone récupère aussi le bilan sans double publication',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      final summary = _payload(h.mediaId, summary: true);
      await h.native(summary);
      h.disposeSummary = summary;
      h.controller.dispose();
      await tester.pump();
      expect(h.reports, hasLength(1));
    } finally {
      await h.close();
    }
  });

  testWidgets('une erreur du rangement du bilan ne casse pas le canal natif',
      (tester) async {
    final h = _NativeHarness(tester);
    await h.attach();
    try {
      NativeVideoController.onPlaybackMetrics =
          (_) => throw StateError('fixture');
      await h.native(_payload(h.mediaId));
      NativeVideoController.onPlaybackMetrics = h.reports.add;
      await h.native(_payload(h.mediaId, summary: true));
      expect(h.reports.single.isSummary, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  test('valeurs indisponibles restent null ; zéro mesuré reste zéro', () {
    final unavailable = NativePlaybackMetrics.readNative(
        _payload(1, summary: true, firstFrame: null))!;
    expect(unavailable.startupMs, isNull);
    expect(unavailable.firstFrameElapsedMs, isNull);
    expect(unavailable.droppedFrames, isNull);
    expect(unavailable.liveOffsetMs, isNull);
    expect(unavailable.toBlackBoxLine(), contains('démarrage_ms=indisponible'));
    final known = NativePlaybackMetrics.readNative(_payload(1, dropped: 0))!;
    expect(known.droppedFrames, 0);
  });

  test('horloges incohérentes, origine inconnue et texte libre sont rejetés',
      () {
    for (final invalid in <Map<String, Object?>>[
      <String, Object?>{..._payload(1), 'origin': 'dart'},
      <String, Object?>{..._payload(1), 'startupMs': 100},
      <String, Object?>{..._payload(1), 'firstFrameElapsedMs': 999},
      <String, Object?>{..._payload(1), 'elapsedMs': 100},
      <String, Object?>{..._payload(1), 'droppedFrames': -1},
      <String, Object?>{..._payload(1), 'liveOffsetMs': 'unknown'},
      <String, Object?>{..._payload(1, summary: true), 'endReason': 'secret'},
    ]) {
      expect(NativePlaybackMetrics.readNative(invalid), isNull);
    }
  });

  test('le texte boîte noire utilise exclusivement les champs autorisés', () {
    final data = <String, Object?>{
      ..._payload(1, summary: true),
      'url': 'https://fixture.invalid/user/password',
      'password': 'private_fixture',
    };
    final line = NativePlaybackMetrics.readNative(data)!.toBlackBoxLine();
    expect(line, contains('origine=android_media3'));
    expect(line, isNot(contains('fixture.invalid')));
    expect(line, isNot(contains('private_fixture')));
  });
}
