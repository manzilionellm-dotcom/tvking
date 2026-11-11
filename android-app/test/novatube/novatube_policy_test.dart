import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_content_policy.dart';
import 'package:tv_king/core/blackbox/black_box_upload.dart';
import 'package:tv_king/core/update/build_flags.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';
import 'package:tv_king/features/channels/data/trending_repository.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/country_home/data/featured_repository.dart';
import 'package:tv_king/features/device/data/device_secret.dart';
import 'package:tv_king/features/panel_board/data/promo_banner_repository.dart';
import 'package:tv_king/features/playlists/data/cloud_backup_repository.dart';
import 'package:tv_king/features/playlists/data/default_servers.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/subscription/data/box_signal_client.dart';
import 'package:tv_king/features/subscription/data/order_ack_client.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
import 'package:tv_king/features/tv/data/home_source_pair.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';

/// Si un ancien service démarre un client réel, le test le voit même si le
/// service absorbe ensuite son exception. Aucun appel externe n'est autorisé.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Le contrat NOVATUBE interdit cet appel au panel.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String mac = 'MK:AA:BB:CC:DD:EE';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('aucune licence ou période d’essai créée au premier lancement', () async {
    final SubscriptionState state = SubscriptionState.instance;
    await state.resetForTesting();
    await state.initialize();
    expect(state.isLoaded, isTrue);
    expect(state.shouldBlockUser, isFalse);
    expect(state.firstLaunchAt, isNull);
    expect(state.status, SubscriptionStatus.unknown);
    expect(state.trialDaysRemaining, 0);
    expect(state.remote.paid, isFalse);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('subscription.first_launch_ms'), isFalse);
    expect(kIsPlayBuild, isTrue);
  });

  test('anciens services incapables de joindre le panel ou importer une source',
      () async {
    final _NoNetwork guard = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      expect((await SubscriptionBackend.heartbeat(mac)).reached, isFalse);
      expect((await SubscriptionBackend.getStatus(mac)).reached, isFalse);
      expect(await SubscriptionState.instance.syncWithBackend(),
          RemoteSyncOutcome.offline);
      expect(await SubscriptionState.instance.refreshRemote(),
          RemoteSyncOutcome.offline);
      expect(await RemoteSourceRepository.sync(force: true),
          RemoteSyncResult.noSource);
      expect(await RemoteSourceRepository.applyRevocations(<String>['fixture']), 0);
      await RemoteSourceRepository.syncHistory();
      expect(await DefaultServersApi.fetch(forceRefresh: true), isEmpty);
      await DeviceSecret.instance.enroll(mac);
      await BlackBoxUpload.instance.send('test');
      await CloudBackupRepository.instance.restoreIfNeeded();
      await CloudBackupRepository.instance.uploadForTesting();
    }, guard);
    expect(guard.attempts, 0);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('device.secret.v1'), isFalse);
  });

  test('QR d’attribution et ordres panel restent inactifs avec un client valide',
      () async {
    int calls = 0;
    final http.Client client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    expect(await publishHomeSourceLink(
      mac: mac,
      post: (_, __, ___) async {
        calls++;
        return 200;
      },
    ), isNull);
    expect((await BoxSignalClient.wait(
      client: client, mac: mac, after: 0, fleetAfter: 0,
    )).orders, isEmpty);
    expect(await BoxSignalClient.ack(
      client: client, mac: mac, boxIds: <int>[1], fleetIds: <int>[],
    ), isFalse);
    expect(await OrderAckClient.send(mac,
      <Map<String, Object?>>[<String, Object?>{'id': 1}], client: client,
    ), isFalse);
    expect(await RemoteActivationWatch.instance.applyOrdersForTesting(
      const <BoxOrder>[
        BoxOrder(id: 1, kind: 'reload_source', fleet: false),
        BoxOrder(id: 2, kind: 'force_update', fleet: false),
      ],
    ), isFalse);
    expect(calls, 0);
  });

  test('aucune publicité, tendance ou promotion téléchargée', () async {
    final _NoNetwork guard = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      await FeaturedRepository.instance.initialize();
      await FeaturedRepository.instance.refresh();
      TrendingRepository.instance.start();
      await PromoBannerRepository.instance.initialize();
      await PromoBannerRepository.instance.refresh();
      expect(await AnnouncementRepository.fetchLatest(), isNull);
      expect((await StartupAdRepository.instance.fetch()).enabled, isFalse);
      expect(await StartupAdRepository.instance.shouldShow(), isFalse);
    }, guard);
    TrendingRepository.instance.stop();
    expect(guard.attempts, 0);
    expect(FeaturedRepository.instance.hasFeatured, isFalse);
    expect(TrendingRepository.instance.current, isEmpty);
    expect(PromoBannerRepository.instance.banners, isEmpty);
  });

  test('classification adulte appliquée au titre comme à la catégorie', () {
    for (final String marker in <String>['XXX', 'ADULT', 'Adultes', '18+']) {
      expect(NovatubeContentPolicy.allows(name: 'Fixture', category: marker),
          isFalse, reason: marker);
      expect(NovatubeContentPolicy.allows(name: marker, category: 'Divers'),
          isFalse, reason: marker);
    }
    expect(NovatubeContentPolicy.allows(
      name: 'Horizons', category: 'Documentaires',
    ), isTrue);
    expect(NovatubeContentPolicy.allows(
      name: 'Finale locale', category: 'Sports',
    ), isTrue);
  });

  test('accès direct à une catégorie adulte refusé avant réseau ou cache',
      () async {
    final _NoNetwork guard = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      final CinemaTitleLoad load = await CinemaRepository.instance.loadTitles(
        CinemaKind.movie,
        const CinemaCategory(
          key: 'fixture', name: 'Fixture',
          parts: <CategoryRef>[CategoryRef('p1', '9')], isAdult: true,
        ),
        forceNetwork: true,
      );
      expect(load.titles, isEmpty);
      expect(load.failed, isFalse);
    }, guard);
    expect(guard.attempts, 0);
  });

  test('ancien historique adulte ne revient pas dans Continuer', () {
    const WatchEntry blocked = WatchEntry(
      id: 'blocked', isEpisode: false, title: 'XXX Fixture',
      streamUrl: 'http://example.invalid/blocked.mp4',
      posMs: 45000, durMs: 900000, updatedAt: 2,
    );
    const WatchEntry allowed = WatchEntry(
      id: 'allowed', isEpisode: false, title: 'Horizons',
      streamUrl: 'http://example.invalid/horizons.mp4',
      posMs: 45000, durMs: 900000, updatedAt: 1,
    );
    final WatchProgressStore store = WatchProgressStore(<WatchEntry>[blocked, allowed]);
    expect(store.continueWatching().map((WatchEntry e) => e.id), <String>['allowed']);
    store.record(blocked);
    store.proposeNext(blocked);
    expect(store.get('blocked'), isNull);
    expect(WatchProgressStore.decode(store.encode()).get('blocked'), isNull);
  });

  test('un titre adulte ne démarre jamais un téléchargement', () async {
    final _NoNetwork guard = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      await DownloadsRepository.instance.start(const VodMovie(
        id: 'adult', name: 'Fixture', category: 'ADULT',
        streamUrl: 'http://example.invalid/blocked.mp4', containerExt: 'mp4',
      ));
    }, guard);
    expect(DownloadsRepository.instance.current, isEmpty);
    expect(guard.attempts, 0);
  });
}
