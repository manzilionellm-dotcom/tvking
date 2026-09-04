// =========================================================
//  family_position_sync_test.dart — « chacun reprend son film », en famille
// =========================================================
//  Transport factice (aucun HTTP). Ce qui est verrouillé :
//    1. l'envoi ne contient JAMAIS l'URL de flux (identifiants du compte) ;
//    2. fusion « le plus récent gagne » dans les deux sens ;
//    3. « terminé » ailleurs retire l'entrée locale plus ancienne ;
//    4. une position reçue sans URL locale : reprise OK, mais absente de la
//       rangée « Continuer » (rien à relancer) ;
//    5. Mode Bouclier (télémétrie minimale) : rien ne part, rien n'est lu ;
//    6. le profil qui change pendant l'attente réseau n'est jamais pollué.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/privacy/privacy_shield.dart';
import 'package:tv_king/features/vod/data/family_position_sync.dart';
import 'package:tv_king/features/vod/data/playback_position_repository.dart';

class _FakeTransport implements FamilyPositionTransport {
  List<Map<String, dynamic>> remote = <Map<String, dynamic>>[];
  final List<List<Map<String, Object?>>> pushed =
      <List<Map<String, Object?>>>[];
  int fetches = 0;
  String? lastProfile;
  bool acceptPush = true;

  @override
  Future<List<Map<String, dynamic>>?> fetch(String mac, String profile) async {
    fetches++;
    lastProfile = profile;
    return remote;
  }

  @override
  Future<bool> push(
      String mac, String profile, List<Map<String, Object?>> items) async {
    lastProfile = profile;
    pushed.add(items);
    return acceptPush;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlaybackPositionRepository repo;
  late FamilyPositionSync sync;
  late _FakeTransport transport;
  final DateTime t0 = DateTime(2026, 9, 1, 20, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrivacyShield.instance.resetForTest();
    repo = PlaybackPositionRepository.instance;
    repo.resetForTest();
    sync = FamilyPositionSync.instance;
    sync.resetForTest();
    transport = _FakeTransport();
    sync.transport = transport;
    sync.macProvider = () async => 'MK:AA:AA:AA:AA:01';
    sync.profileProvider = () => 'papa';
    sync.enabled = true;
  });

  tearDown(() {
    sync.resetForTest();
    repo.resetForTest();
    PrivacyShield.instance.resetForTest();
  });

  test('l\'envoi ne contient jamais l\'URL de flux', () async {
    await repo.record(
      key: 'vod-100',
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 100),
      name: 'Film A',
      streamUrl: 'http://panel/movie/user/secret/100.mp4',
      at: t0,
    );
    await sync.pushNow();
    expect(transport.pushed, hasLength(1));
    expect(transport.lastProfile, 'papa');
    final Map<String, Object?> item = transport.pushed.single.single;
    expect(item['key'], 'vod-100');
    expect(item['position_ms'], 600000);
    expect(item['finished'], isFalse);
    expect(transport.pushed.toString().contains('secret'), isFalse);
    expect(item.containsKey('streamUrl'), isFalse);
    expect(item.containsKey('stream_url'), isFalse);
  });

  test('un second envoi ne renvoie que ce qui a changé', () async {
    await repo.record(
      key: 'vod-1',
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 50),
      name: 'A',
      streamUrl: 'http://x/1',
      at: t0,
    );
    await sync.pushNow();
    await sync.pushNow();
    expect(transport.pushed, hasLength(1), reason: 'rien de neuf → rien envoyé');
    await repo.record(
      key: 'vod-2',
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 50),
      name: 'B',
      streamUrl: 'http://x/2',
      at: DateTime.now(),
    );
    await sync.pushNow();
    expect(transport.pushed, hasLength(2));
    expect(transport.pushed.last.single['key'], 'vod-2');
  });

  test('fusion : la position distante plus récente gagne, l\'URL locale reste',
      () async {
    await repo.record(
      key: 'vod-100',
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 100),
      name: 'Film A',
      streamUrl: 'http://x/100',
      at: t0,
    );
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'vod-100',
        'position_ms': 30 * 60 * 1000,
        'duration_ms': 100 * 60 * 1000,
        'finished': false,
        'updated_at': t0.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        'name': 'Film A',
      },
    ];
    expect(await sync.pullNow(), 1);
    final PlaybackPosition e = repo.entryFor('vod-100')!;
    expect(e.position, const Duration(minutes: 30));
    expect(e.streamUrl, 'http://x/100', reason: 'l\'URL locale est conservée');
    expect(repo.entries.map((PlaybackPosition p) => p.key), contains('vod-100'));
  });

  test('fusion : une position distante plus ancienne est ignorée', () async {
    await repo.record(
      key: 'vod-100',
      position: const Duration(minutes: 40),
      duration: const Duration(minutes: 100),
      name: 'Film A',
      streamUrl: 'http://x/100',
      at: t0,
    );
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'vod-100',
        'position_ms': 5 * 60 * 1000,
        'duration_ms': 100 * 60 * 1000,
        'updated_at':
            t0.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      },
    ];
    expect(await sync.pullNow(), 0);
    expect(repo.positionFor('vod-100'), const Duration(minutes: 40));
  });

  test('« terminé » ailleurs retire l\'entrée locale plus ancienne', () async {
    await repo.record(
      key: 'ep-7',
      position: const Duration(minutes: 3),
      duration: const Duration(minutes: 40),
      name: 'S1 E2',
      streamUrl: 'http://x/7',
      isEpisode: true,
      at: t0,
    );
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'ep-7',
        'finished': true,
        'updated_at': t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      },
    ];
    expect(await sync.pullNow(), 1);
    expect(repo.positionFor('ep-7'), isNull);
  });

  test('terminé localement → tombstone poussée', () async {
    await repo.record(
      key: 'vod-9',
      position: const Duration(minutes: 3),
      duration: const Duration(minutes: 40),
      name: 'X',
      streamUrl: 'http://x/9',
      at: t0,
    );
    await sync.pushNow();
    await repo.markFinished('vod-9');
    await sync.pushNow();
    final Map<String, Object?> last = transport.pushed.last.single;
    expect(last['key'], 'vod-9');
    expect(last['finished'], isTrue);
  });

  test('reçue sans URL locale : reprise oui, rangée « Continuer » non',
      () async {
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'vod-555',
        'position_ms': 20 * 60 * 1000,
        'duration_ms': 90 * 60 * 1000,
        'updated_at': t0.millisecondsSinceEpoch,
        'name': 'Vu sur le téléphone',
      },
    ];
    expect(await sync.pullNow(), 1);
    expect(repo.positionFor('vod-555'), const Duration(minutes: 20));
    expect(repo.progressFor('vod-555'), closeTo(20 / 90, 0.001));
    expect(repo.entries.where((PlaybackPosition p) => p.key == 'vod-555'),
        isEmpty);
    expect(repo.allEntries.where((PlaybackPosition p) => p.key == 'vod-555'),
        hasLength(1));
  });

  test('Mode Bouclier : rien ne part, rien n\'est lu', () async {
    await PrivacyShield.instance.setEnabled(true);
    await PrivacyShield.instance.setMinimalTelemetry(true);
    await repo.record(
      key: 'vod-1',
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 50),
      name: 'A',
      streamUrl: 'http://x/1',
      at: t0,
    );
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'vod-2',
        'position_ms': 1000,
        'duration_ms': 100000,
        'updated_at': t0.millisecondsSinceEpoch,
      },
    ];
    await sync.pushNow();
    expect(await sync.pullNow(), 0);
    expect(transport.pushed, isEmpty);
    expect(transport.fetches, 0);
    expect(repo.positionFor('vod-2'), isNull);
  });

  test('le profil change pendant l\'attente réseau → rien appliqué',
      () async {
    String current = 'papa';
    sync.profileProvider = () => current;
    transport.remote = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'vod-1',
        'position_ms': 1000,
        'duration_ms': 100000,
        'updated_at': t0.millisecondsSinceEpoch,
      },
    ];
    // Le transport factice répond tout de suite : on simule le changement
    // de profil en le faisant basculer DANS fetch.
    final _FakeTransport switching = _FakeTransport()
      ..remote = transport.remote;
    sync.transport = _SwitchingTransport(switching, () => current = 'maman');
    expect(await sync.pullNow(), 0);
    expect(repo.positionFor('vod-1'), isNull);
  });
}

class _SwitchingTransport implements FamilyPositionTransport {
  _SwitchingTransport(this.inner, this.onFetch);
  final _FakeTransport inner;
  final void Function() onFetch;

  @override
  Future<List<Map<String, dynamic>>?> fetch(String mac, String profile) async {
    onFetch();
    return inner.fetch(mac, profile);
  }

  @override
  Future<bool> push(
          String mac, String profile, List<Map<String, Object?>> items) =>
      inner.push(mac, profile, items);
}
