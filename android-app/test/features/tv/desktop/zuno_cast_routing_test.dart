// Tests de raccordement de la vraie sélection Accueil/Direct au moteur Cast.
// Les transports sont simulés ; aucune URL de fournisseur n'est contactée.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/cast/presentation/cast_picker_sheet.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'zuno_mobile_cast_controls_test.dart' show Receiver;

const _capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
const _device = CastDevice(
    id: 'fixture',
    name: 'TV test',
    kind: CastDeviceKind.googleCast,
    host: '192.0.2.1',
    port: 8009,
    controlUrl: 'http://192.0.2.1');
const _one = Channel(
    id: 'one',
    name: 'Information',
    category: 'Info',
    streamUrl: 'https://stream.invalid/one.ts',
    isLive: true,
    playlistId: 1);
const _two = Channel(
    id: 'two',
    name: 'Sport',
    category: 'Sport',
    streamUrl: 'https://stream.invalid/two.ts',
    isLive: true,
    playlistId: 1);
const _adult = Channel(
    id: 'adult',
    name: 'Adult XXX',
    category: 'Adultes',
    streamUrl: 'https://stream.invalid/adult.ts',
    isLive: true,
    playlistId: 1);
const _foreign = Channel(
    id: 'foreign',
    name: 'Autre profil',
    category: 'Info',
    streamUrl: 'https://stream.invalid/foreign.ts',
    isLive: true,
    playlistId: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_capability, (_) async => true);
    await CastPlatform.initializeZuno();
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: <int>[1]);
  });
  tearDown(() {
    ActiveProfile.instance.set(ProfileIds.origin);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_capability, null);
  });

  CastManager makeManager(Receiver receiver,
          {Future<StreamProbeResult> Function(String)? probe}) =>
      CastManager.forTesting(
        transportFactory: (_) => receiver,
        probe: probe ??
            (url) async => StreamProbeResult(
                originalUrl: url, finalUrl: url, success: true),
        discoverSsdp: (_) => Stream<CastDevice>.value(_device),
      );

  Future<BuildContext> host(WidgetTester tester, {Widget? child}) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: Builder(builder: (value) {
        context = value;
        return child ?? const SizedBox();
      })),
    ));
    return context;
  }

  testWidgets('Accueil/Direct envoie à la TV après libération de l’aperçu',
      (tester) async {
    final events = <String>[];
    final receiver = Receiver(events);
    final manager = makeManager(receiver)..selectDevice(_device);
    final context = await host(tester);
    final released = Completer<void>();
    bool? routed;
    final pending = routeZunoChannelToCast(context,
        channels: const <Channel>[_one, _two, _adult, _foreign],
        channel: _two,
        manager: manager, releaseLocal: () async {
      events.add('preview-stopping');
      await released.future;
      events.add('preview-stopped');
    }).then((value) => routed = value);
    await tester.pump();
    expect(receiver.urls, isEmpty);
    released.complete();
    await pending;
    expect(routed, isTrue);
    expect(events.take(3),
        <String>['preview-stopping', 'preview-stopped', 'remote-play']);
    expect(receiver.urls, <String>[_two.streamUrl]);
    expect(manager.currentCastChannel, _two);
    expect(manager.canZapOnCast, isTrue);
    await manager.zapCastNext();
    expect(receiver.urls.last, _one.streamUrl,
        reason: 'le zap garde la liste sûre, sans Adultes ni source étrangère');
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'un changement de profil pendant le handoff interdit l’ancien flux',
      (tester) async {
    final receiver = Receiver(<String>[]);
    final manager = makeManager(receiver)..selectDevice(_device);
    final context = await host(tester);
    final released = Completer<void>();
    final pending = routeZunoChannelToCast(context,
        channels: const <Channel>[_one, _two],
        channel: _one,
        manager: manager,
        releaseLocal: () => released.future);
    ActiveProfile.instance.set('nouveau-profil', playlistIds: <int>[2]);
    released.complete();
    expect(await pending, isTrue,
        reason:
            'la sélection annulée ne doit pas retomber sur le lecteur local');
    expect(receiver.urls, isEmpty);
    expect(manager.hasTarget, isFalse);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('deux choix rapides ne rétablissent pas la première chaîne',
      (tester) async {
    final receiver = Receiver(<String>[]);
    final manager = makeManager(receiver)..selectDevice(_device);
    final context = await host(tester);
    final released = Completer<void>();
    final first = routeZunoChannelToCast(context,
        channels: const <Channel>[_one, _two],
        channel: _one,
        manager: manager,
        releaseLocal: () => released.future);
    await routeZunoChannelToCast(context,
        channels: const <Channel>[_one, _two],
        channel: _two,
        manager: manager,
        releaseLocal: () async {});
    released.complete();
    await first;
    expect(receiver.urls, <String>[_two.streamUrl]);
    expect(manager.currentCastChannel, _two);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('fermer le vrai sélecteur annule sa connexion en attente',
      (tester) async {
    final receiver = Receiver(<String>[]);
    final probe = Completer<StreamProbeResult>();
    final manager = makeManager(receiver, probe: (_) => probe.future);
    final context = await host(tester);
    final picker = showCastPicker(context,
        streamUrl: _one.streamUrl, title: _one.name, manager: manager);
    await tester.pumpAndSettle();
    expect(find.text(_device.name), findsOneWidget);
    await tester.tap(find.text(_device.name));
    await tester.pump();
    expect(manager.state, CastState.connecting);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isFalse);
    probe.complete(StreamProbeResult(
        originalUrl: _one.streamUrl, finalUrl: _one.streamUrl, success: true));
    for (int i = 0; i < 6; i++) {
      await tester.pump();
    }
    await picker;
    expect(receiver.urls, isEmpty);
    expect(manager.hasActiveSession, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('le sélecteur disparaît au changement de profil', (tester) async {
    final receiver = Receiver(<String>[]);
    final manager = makeManager(receiver);
    final context = await host(tester);
    final picker = showCastPicker(context,
        streamUrl: _one.streamUrl, title: _one.name, manager: manager);
    await tester.pumpAndSettle();
    expect(find.byType(CastPickerSheet), findsOneWidget);
    ActiveProfile.instance.set('autre-profil', playlistIds: <int>[2]);
    await tester.pumpAndSettle();
    await picker;
    expect(find.byType(CastPickerSheet), findsNothing);
    expect(receiver.urls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
