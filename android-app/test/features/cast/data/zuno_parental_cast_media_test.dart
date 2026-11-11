import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/zuno_cast_media.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

import 'cast_parental_fixture.dart';

const _url = 'https://fixture.invalid/film.mp4';
const _known =
    ZunoCastMedia(id: 'vod-7', streamUrl: _url, playlistId: 7, isAdult: false);

class _RetryTransport extends ParentalTransport {
  bool failNext = true;

  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'ZUNO',
      String? imageUrl}) async {
    if (failNext) {
      failNext = false;
      throw Exception('Échec contrôlé avant la relance du picker');
    }
    await super
        .playStream(streamUrl: streamUrl, title: title, imageUrl: imageUrl);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => prepareCastProfile());
  tearDown(() {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    ActiveProfile.instance.set('p1');
  });

  Future<void> expectMedia(ZunoCastMedia media, bool allowed) async {
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: media.streamUrl, title: 'Film', zunoMedia: media);
      expect(receiver.played.length, allowed ? 1 : 0);
      if (allowed) expect(manager.state, CastState.casting);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  }

  test('Enfants : VOD classée non adulte de sa source reste utilisable',
      () async {
    await expectMedia(_known, true);
  });

  test('Enfants : le picker peut réessayer le même média connu après erreur',
      () async {
    final receiver = _RetryTransport();
    final manager = parentalManager(receiver);
    try {
      await expectLater(
          manager.castTo(parentalDevice,
              streamUrl: _url, title: 'Film', zunoMedia: _known),
          throwsException);
      await manager.castTo(parentalDevice, streamUrl: _url, title: 'Film');
      expect(receiver.played, hasLength(1));
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });
  test('Enfants : VOD non classée refusée', () async {
    await expectMedia(
        const ZunoCastMedia(id: 'unknown', streamUrl: _url, playlistId: 7),
        false);
  });
  test('Enfants : VOD adulte refusée', () async {
    await expectMedia(
        const ZunoCastMedia(
            id: 'adult', streamUrl: _url, playlistId: 7, isAdult: true),
        false);
  });
  test('Enfants : classement seul ne donne pas accès à une autre source',
      () async {
    await expectMedia(
        const ZunoCastMedia(
            id: 'other-source', streamUrl: _url, playlistId: 8, isAdult: false),
        false);
  });

  test('un contexte ancien ne récupère pas les droits du nouveau profil',
      () async {
    final access = _known.capture();
    await prepareCastProfile(kids: false, sources: null);
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      manager.setZunoMediaAccess(access);
      await manager.castTo(parentalDevice, streamUrl: _url, title: 'Film');
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('un contexte ne peut autoriser une autre URL avec le même titre',
      () async {
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      manager.setZunoMediaAccess(_known.capture());
      await manager.castTo(parentalDevice,
          streamUrl: 'https://fixture.invalid/autre.mp4', title: 'Film');
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('profil remplacé pendant le probe : aucune lecture tardive', () async {
    final entered = Completer<void>();
    final response = Completer<StreamProbeResult>();
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver, probe: (_) {
      entered.complete();
      return response.future;
    });
    try {
      final operation = manager.castTo(parentalDevice,
          streamUrl: _url, title: 'Film', zunoMedia: _known);
      await entered.future;
      await prepareCastProfile(kids: false, sources: null);
      response.complete(const StreamProbeResult(
          originalUrl: _url, finalUrl: _url, success: true));
      await operation;
      expect(receiver.played, isEmpty);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('le contexte de session conserve une VOD autorisée après le geste',
      () async {
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      manager.setZunoMediaAccess(_known.capture());
      await manager.castTo(parentalDevice, streamUrl: _url, title: 'Film');
      // Le picker et le widget n'ont aucun callback de validité à maintenir.
      manager.setZunoMediaAccess(null);
      await manager.pause();
      await manager.resume();
      expect(manager.state, CastState.casting);
      expect(receiver.played, hasLength(1));
      await ParentalControls.instance.load();
      expect(manager.state, CastState.idle,
          reason:
              'Une nouvelle génération de restrictions expire le contexte.');
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('adulte à sources limitées : URL brute refusée, média connu autorisé',
      () async {
    await prepareCastProfile(kids: false);
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice, streamUrl: _url, title: 'Film');
      expect(receiver.played, isEmpty);
      await manager.castTo(parentalDevice,
          streamUrl: _url, title: 'Film', zunoMedia: _known);
      expect(receiver.played, hasLength(1));
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('adulte sans restriction de sources : URL directe conservée', () async {
    await prepareCastProfile(kids: false, sources: null);
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice, streamUrl: _url, title: 'Film');
      expect(receiver.played, hasLength(1));
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });
}
