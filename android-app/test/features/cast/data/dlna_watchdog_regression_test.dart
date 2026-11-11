// Scénarios portables : uniquement les API existantes du build 116.
// Le faux récepteur traite les véritables actions SOAP du transport ; le
// temps simulé conserve un tick de 10 s et une réponse STOPPED de 12 s.
import 'dart:async';

// Fourni par flutter_test avec le SDK figé ; aucune dépendance applicative
// n'est ajoutée pour piloter les vrais délais des sondes de ce test portable.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

class _Receiver {
  _Receiver(this.id);
  final String id;
  String state = 'STOPPED';
  bool slowStopped = false;
  bool failNextRead = false;
  int timeoutReads = 0;
  int setUris = 0;
  int reads = 0;
  final List<String> actions = <String>[];

  CastDevice get device => CastDevice(
      id: id,
      name: 'Récepteur de test',
      kind: CastDeviceKind.dlna,
      host: '127.0.0.1',
      port: 8060,
      controlUrl: 'http://127.0.0.1:8060/$id/AVTransport/control');

  Future<http.Response> handle(http.Request request) async {
    final action =
        (request.headers['SOAPAction'] ?? request.headers['soapaction'] ?? '')
            .split('#')
            .last
            .replaceAll('"', '');
    actions.add(action);
    if (action == 'GetProtocolInfo') {
      return http.Response(
          '<Envelope><Body><GetProtocolInfoResponse>'
          '<Sink>http-get:*:video/mp2t:*</Sink>'
          '</GetProtocolInfoResponse></Body></Envelope>',
          200);
    }
    if (action == 'GetTransportInfo') {
      reads++;
      if (failNextRead) {
        failNextRead = false;
        throw StateError('Erreur de sonde contrôlée');
      }
      final snapshot = state;
      if (timeoutReads > 0) {
        timeoutReads--;
        await Future<void>.delayed(const Duration(seconds: 30));
      } else if (slowStopped && state == 'STOPPED') {
        await Future<void>.delayed(const Duration(seconds: 12));
      }
      return http.Response(
          '<Envelope><Body><GetTransportInfoResponse>'
          '<CurrentTransportState>$snapshot</CurrentTransportState>'
          '</GetTransportInfoResponse></Body></Envelope>',
          200);
    }
    if (action == 'Stop') {
      state = 'STOPPED';
      slowStopped = false;
    } else if (action == 'SetAVTransportURI') {
      setUris++;
      state = 'STOPPED';
    } else if (action == 'Play') {
      state = 'PLAYING';
    } else if (action == 'Pause') {
      state = 'PAUSED_PLAYBACK';
    }
    return http.Response(
        '<Envelope><Body><${action}Response/></Body></Envelope>', 200);
  }

  void cut({bool slow = true}) {
    state = 'STOPPED';
    slowStopped = slow;
  }
}

void _scenario(
    void Function(FakeAsync, CastManager, _Receiver, _Receiver) run) {
  fakeAsync((clock) {
    final first = _Receiver('watchdog-a');
    final second = _Receiver('watchdog-b');
    final manager = CastManager.forTesting(
      transportFactory: (device) => UpnpAvTransport(device),
      probe: (url) async => StreamProbeResult(
          originalUrl: url, finalUrl: url, success: true, mime: 'video/mp2t'),
      timeout: const Duration(minutes: 3),
    );
    final errors = <Object>[];
    http.runWithClient(() {
      manager
          .castTo(first.device,
              streamUrl: 'http://fixture.invalid/watchdog.ts', title: 'Journal')
          .catchError((Object error) {
        errors.add(error);
      });
      clock.flushMicrotasks();
      expect(errors, isEmpty);
      expect(manager.state, CastState.casting);
      expect(first.setUris, 1);
      try {
        run(clock, manager, first, second);
      } finally {
        unawaited(manager.disconnect());
        clock.flushMicrotasks();
        manager.dispose();
        clock.flushMicrotasks();
      }
    },
        () => MockClient((request) => request.url.path.contains('watchdog-b')
            ? second.handle(request)
            : first.handle(request)));
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.kids_mode.v1': false,
      'profiles.catalog.v1': ProfileCatalog.fresh().encode(),
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.configureZuno(isAndroidHandset: false);
    RepairFlags.debugReset();
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    ActiveProfile.instance.set('p1');
  });

  test('STOPPED après 12 s : une seule SetURI par coupure', () {
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 35));
      expect(first.setUris - 1, 1,
          reason: 'La sonde de t=20 ne doit pas doubler celle de t=10.');
      expect(manager.state, CastState.casting);
    });
  });

  test('Pause pendant GetTransportInfo interdit la relance tardive', () {
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 11));
      unawaited(manager.pause());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 24));
      expect(first.setUris, 1);
      expect(manager.state, CastState.paused);
    });
  });

  test('Stop pendant la sonde invalide sa réponse', () {
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 11));
      unawaited(manager.disconnect());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 25));
      expect(first.setUris, 1);
      expect(manager.state, CastState.idle);
    });
  });

  test('ancien finally ne libère pas le propriétaire de la nouvelle session',
      () {
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 11));
      unawaited(manager.castTo(second.device,
          streamUrl: 'http://fixture.invalid/next.ts',
          title: 'Journal suivant'));
      clock.flushMicrotasks();
      expect(second.setUris, 1);
      second.cut();
      clock.elapse(const Duration(seconds: 41));
      expect(first.setUris, 1);
      expect(second.setUris - 1, 1,
          reason: 'Observe jusqu’à t=52, après le retour obsolète de t=43.');
    });
  });

  test('changement de profil pendant la sonde ferme la session', () {
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 11));
      ActiveProfile.instance.set('p2', playlistIds: const <int>[]);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 25));
      expect(first.setUris, 1);
      expect(manager.state, CastState.idle);
    });
  });

  test('une erreur de sonde ne conserve pas le verrou', () {
    _scenario((clock, manager, first, second) {
      first.failNextRead = true;
      clock.elapse(const Duration(seconds: 11));
      first.cut(slow: false);
      clock.elapse(const Duration(seconds: 15));
      expect(first.setUris - 1, 1);
    });
  });

  test('timeout puis réponse tardive : le prochain tick reste utilisable', () {
    _scenario((clock, manager, first, second) {
      first.cut(slow: false);
      first.timeoutReads = 1;
      clock.elapse(const Duration(seconds: 50));
      expect(first.setUris - 1, 1);
      expect(manager.state, CastState.casting);
    });
  });

  test('7 MOTION conserve explicitement sa surveillance historique', () {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    _scenario((clock, manager, first, second) {
      first.cut();
      clock.elapse(const Duration(seconds: 35));
      expect(first.setUris - 1, 2);
    });
  });
}
