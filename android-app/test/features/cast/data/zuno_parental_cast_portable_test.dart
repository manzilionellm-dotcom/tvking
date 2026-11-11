// API du 116 uniquement : ces scénarios restent exécutables sur la référence.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

import 'cast_parental_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => prepareCastProfile());
  tearDown(() {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    ActiveProfile.instance.set('p1');
  });

  test('Enfants : une URL sans métadonnées ne part pas au récepteur', () async {
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: 'https://fixture.invalid/inconnu.mp4', title: 'Vidéo');
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('Enfants : une chaîne non classée reste interdite par accès indirect',
      () async {
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    const unknown = Channel(
        id: 'unknown',
        name: 'Mystère',
        category: '',
        streamUrl: 'https://fixture.invalid/unknown.ts',
        isLive: true,
        playlistId: 7);
    try {
      manager.selectDevice(parentalDevice);
      manager.setCastPlaylist([unknown], unknown);
      final played = await manager.castChannelOnCurrentSession(
          streamUrl: unknown.streamUrl, title: unknown.name, channel: unknown);
      expect(played, isFalse);
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('restrictions modifiées pendant le probe interdisent le Play tardif',
      () async {
    await prepareCastProfile(kids: false, sources: null);
    final entered = Completer<void>();
    final response = Completer<StreamProbeResult>();
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver, probe: (_) {
      entered.complete();
      return response.future;
    });
    try {
      final operation = manager.castTo(parentalDevice,
          streamUrl: 'https://fixture.invalid/inconnu.mp4', title: 'Vidéo');
      await entered.future;
      ParentalControls.instance.kidsMode.value = true;
      response.complete(const StreamProbeResult(
          originalUrl: 'https://fixture.invalid/inconnu.mp4',
          finalUrl: 'https://fixture.invalid/inconnu.mp4',
          success: true));
      await operation;
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('7 MOTION conserve son accès historique par URL', () async {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: 'https://fixture.invalid/inconnu.mp4', title: 'Vidéo');
      expect(receiver.played, hasLength(1));
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });
}
