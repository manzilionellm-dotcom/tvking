import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/tv/presentation/tv_channel_guide_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  final now = DateTime.now();
  EpgProgram show(String title, int hours, {String id = 'max-channel'}) {
    final start = now.add(Duration(hours: hours)).millisecondsSinceEpoch;
    return EpgProgram(channelId: id, title: title, startTime: start,
        stopTime: start + const Duration(minutes: 45).inMilliseconds);
  }
  final past = show('Journal de la veille', -14);
  final next = show('Un match demain', 24);
  final expired = show('Une ancienne finale', -96);
  const channel = Channel(id: 'max-channel', name: 'Chaîne test', category: 'Test',
      isLive: true, streamUrl: 'https://example.invalid/u/p/7.ts',
      catchupSupported: true, catchupDays: 1);

  testWidgets('Guide MAX, programme à venir, archive expirée et replay à la télécommande',
      (tester) async {
    expect(kNovatubeTvName, 'MAXTUBE');
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    addTearDown(() => BoxMemoryBudget.debugTier = null);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    EpgProgram? selected;
    await tester.pumpWidget(MaterialApp(locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Scaffold(body: TextButton(child: const Text('ouvrir'),
        onPressed: () async {
          selected = await Navigator.push(context, MaterialPageRoute<EpgProgram>(
            builder: (_) => TvChannelGuideScreen(channel: channel,
              loadPrograms: (_) async => [past, next, expired],
              loadHistory: (_) async => [expired]),
          ));
        })))));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text(next.title), findsOneWidget);
    expect(find.text(past.title), findsNothing);
    await tester.tap(find.text(next.title));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('REPLAY'), findsNothing);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(expired.title));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replay indisponible pour cette émission.'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Émissions passées'));
    await tester.pumpAndSettle();
    expect(find.text(expired.title), findsNothing);
    expect(find.text('REPLAY'), findsOneWidget);
    final row = tester.widgetList<Focus>(find.descendant(
      of: find.byKey(const ValueKey<String>('guide-row-0')), matching: find.byType(Focus),
    )).firstWhere((f) => f.focusNode != null);
    row.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected?.title, past.title);
    expect(tester.takeException(), isNull);
  });

  test('Historique SQLite par profil, dédoublonnage, plafond et retrait de liste', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('novatube-max-guide');
    final db = PlaylistDatabase.instance;
    PlaylistDatabase.debugFilePath = '${directory.path}/max.db';
    final history = RecentlyWatchedRepository.instance;
    addTearDown(() async {
      ActiveProfile.instance.set('p1');
      await db.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await directory.delete(recursive: true);
    });
    await history.recordProgram('p1', past, now);
    await history.recordProgram('p1', past, now);
    expect((await history.watchedPrograms(channel.id)).length, 1);
    ActiveProfile.instance.set('p2');
    expect(await history.watchedPrograms(channel.id), isEmpty);
    await history.recordProgram('p1', past, now);
    for (int i = 0; i < 102; i++) {
      await history.recordProgram('p2', show('Titre $i', -i - 1), now.add(Duration(seconds: i)));
    }
    final items = await history.watchedPrograms(channel.id);
    expect(items.length, 100);
    expect(items.first.title, 'Titre 101');
    await history.clear();
    expect(await history.watchedPrograms(channel.id), isEmpty);
    ActiveProfile.instance.set('p1');
    expect((await history.watchedPrograms(channel.id)).single.title, past.title);
    await history.forgetChannels([channel.id]);
    expect(await history.watchedPrograms(channel.id), isEmpty);
  });
}
