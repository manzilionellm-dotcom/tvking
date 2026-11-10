import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'zuno_mobile_cast_controls_test.dart' show LocalPlayer, Receiver;

const _capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
const _device = CastDevice(
  id: 'fixture',
  name: 'Écran test',
  kind: CastDeviceKind.roku,
  host: '192.0.2.1',
  port: 8060,
  controlUrl: 'http://192.0.2.1',
);
const _url = 'http://stream.invalid/live.ts';

Future<AdultAccessGrant> _grant() async {
  // Authentification réelle du module par le PIN de test, sans biométrie.
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_capability, (_) async => false);
  await CastPlatform.initializeZuno();
  final grant = await authenticateAdultAccess(
    reason: 'Test session protégée',
    confirmPin: () async => true,
  );
  expect(grant, isNotNull);
  messenger.setMockMethodCallHandler(_capability, (_) async => true);
  await CastPlatform.initializeZuno();
  return grant!;
}

CastManager _manager(Receiver receiver,
        {Future<StreamProbeResult> Function(String)? probe}) =>
    CastManager.forTesting(
      transportFactory: (_) => receiver,
      probe: probe ??
          (url) async => StreamProbeResult(
                originalUrl: url,
                finalUrl: url,
                success: true,
              ),
    );

Widget _controls(
        CastManager manager, LocalPlayer local, AdultAccessGrant grant) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(
          body: DesktopCastControls(
        controller: local,
        manager: manager,
        streamUrl: _url,
        title: 'Programme test',
        adultAccess: grant,
        picker: (context,
            {required streamUrl, required title, imageUrl, adultAccess}) {
          expect(identical(adultAccess, grant), isTrue);
          return manager.castTo(_device,
              streamUrl: streamUrl, title: title, adultAccess: adultAccess);
        },
      )),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRepository.instance.resetForTesting(ProfileCatalog(
      profiles: <FamilyProfile>[FamilyProfile.origin()],
      activeId: ProfileIds.origin,
      askOnStartup: null,
    ));
    ParentalControls.instance.kidsMode.value = false;
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_capability, null));

  testWidgets('le Cast protégé reste révocable après fermeture du lecteur',
      (tester) async {
    final grant = (await tester.runAsync(_grant))!;
    final events = <String>[];
    final local = LocalPlayer(events);
    final manager = _manager(Receiver(events));
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
      grant.dispose();
    });
    await tester.pumpWidget(_controls(manager, local, grant));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(manager.isCasting, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(manager.isCasting, isTrue);
    grant.revoke();
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isFalse);
    expect(events, contains('remote-stop'));
    expect(events, isNot(contains('local-resume')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('révoquer le droit ne coupe pas un Cast normal préexistant',
      (tester) async {
    final grant = (await tester.runAsync(_grant))!;
    final events = <String>[];
    final local = LocalPlayer(events);
    final manager = _manager(Receiver(events));
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
      grant.dispose();
    });
    await manager.castTo(_device, streamUrl: _url, title: 'Normal');
    await tester.pumpWidget(_controls(manager, local, grant));
    await tester.pumpAndSettle();
    grant.revoke();
    await tester.pumpAndSettle();
    expect(manager.isCasting, isTrue);
    expect(events, isNot(contains('remote-stop')));
    expect(events, isNot(contains('local-resume')));
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('révocation pendant la connexion interdit un démarrage tardif',
      (tester) async {
    final grant = (await tester.runAsync(_grant))!;
    final events = <String>[];
    final probe = Completer<StreamProbeResult>();
    final receiver = Receiver(events);
    final manager = _manager(receiver, probe: (_) => probe.future);
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      grant.dispose();
    });
    final pending = manager
        .castTo(_device,
            streamUrl: _url, title: 'Programme test', adultAccess: grant)
        .catchError((Object _) {});
    await tester.pump();
    expect(manager.hasActiveSession, isTrue);
    grant.revoke();
    probe.complete(
        StreamProbeResult(originalUrl: _url, finalUrl: _url, success: true));
    await pending;
    await tester.pump();
    expect(manager.hasActiveSession, isFalse);
    expect(receiver.urls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('un nouveau Cast normal ne garde pas le grant précédent',
      (tester) async {
    final grant = (await tester.runAsync(_grant))!;
    final events = <String>[];
    final manager = _manager(Receiver(events));
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      grant.dispose();
    });
    await manager.castTo(_device,
        streamUrl: _url, title: 'Programme test', adultAccess: grant);
    await manager.castTo(_device,
        streamUrl: 'http://stream.invalid/normal.ts', title: 'Normal');
    final stopsBefore = events.where((e) => e == 'remote-stop').length;
    grant.revoke();
    await tester.pump();
    expect(manager.isCasting, isTrue);
    expect(events.where((e) => e == 'remote-stop').length, stopsBefore);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('un zap en attente ne remplace pas une nouvelle session normale',
      (tester) async {
    final grant = (await tester.runAsync(_grant))!;
    final events = <String>[];
    final receiver = Receiver(events);
    final manager = _manager(receiver);
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      grant.dispose();
    });
    const nextUrl = 'http://stream.invalid/next.ts';
    const normalUrl = 'http://stream.invalid/normal.ts';
    final channels = <Channel>[
      Channel(
          id: 'one',
          name: 'Un',
          category: 'Test',
          streamUrl: _url,
          isLive: true),
      Channel(
          id: 'two',
          name: 'Deux',
          category: 'Test',
          streamUrl: nextUrl,
          isLive: true),
    ];
    await manager.castTo(_device,
        streamUrl: _url, title: 'Programme test', adultAccess: grant);
    manager.setCastPlaylist(channels, channels.first, adultAccess: grant);
    final oldZap = manager.zapCastNext();
    final replacement =
        manager.castTo(_device, streamUrl: normalUrl, title: 'Normal');
    await Future.wait(<Future<void>>[oldZap, replacement]);
    grant.revoke();
    await tester.pump();
    expect(receiver.urls.last, normalUrl);
    expect(receiver.urls, isNot(contains(nextUrl)));
    expect(manager.isCasting, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
