import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

const parentalDevice = CastDevice(
    id: 'parental-fixture',
    name: 'TV locale',
    kind: CastDeviceKind.roku,
    host: '127.0.0.1',
    port: 8060,
    controlUrl: 'http://127.0.0.1:8060');

class ParentalTransport implements CastTransport {
  final List<String> played = <String>[];
  int stops = 0;
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Fixture',
      String? imageUrl}) async {
    played.add(streamUrl);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

Future<void> prepareCastProfile(
    {bool kids = true, List<int>? sources = const [7]}) async {
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  AppPlatform.configureZuno(isAndroidHandset: true);
  final origin = FamilyProfile.origin();
  final person = FamilyProfile(
      id: 'fixture_profile',
      name: 'Profil fixe',
      avatar: 1,
      isKids: kids,
      createdAtMs: 0,
      playlistIds: sources);
  final catalog = ProfileCatalog(
      profiles: [origin, person], activeId: person.id, askOnStartup: false);
  SharedPreferences.setMockInitialValues(<String, Object>{
    ProfileKeys.catalog: catalog.encode(),
    ProfileKeys.kidsMode(person.id): kids,
  });
  ProfileRepository.instance.resetForTesting(catalog);
  await ParentalControls.instance.load();
}

CastManager parentalManager(ParentalTransport receiver,
        {Future<StreamProbeResult> Function(String)? probe}) =>
    CastManager.forTesting(
      transportFactory: (_) => receiver,
      probe: probe ??
          (url) async =>
              StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      timeout: const Duration(seconds: 5),
    );
