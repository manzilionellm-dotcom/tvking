// Guide d'une chaîne (TV) : pastille « REPLAY » sur les émissions terminées
// d'une chaîne à catch-up, et OK qui rend le programme au lecteur.
// Programmes fictifs injectés (aucune base, aucun réseau).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/epg/domain/replay_choice.dart';
import 'package:tv_king/features/tv/presentation/tv_channel_guide_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

Channel _channel({bool catchup = true, int? days}) => Channel(
      id: 'xtream-55',
      name: 'Chaîne test',
      category: 'Cat',
      streamUrl: 'http://tv.invalid:8080/user/pass/55.ts',
      isLive: true,
      catchupSupported: catchup,
      catchupDays: days,
    );

EpgProgram _program(String title, DateTime start, int minutes) => EpgProgram(
      channelId: 'xtream-55',
      startTime: start.millisecondsSinceEpoch,
      stopTime: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
      title: title,
    );

List<EpgProgram> _day(DateTime now) => <EpgProgram>[
      _program('Journal du matin', now.subtract(const Duration(hours: 3)), 60),
      _program('Le film', now.subtract(const Duration(hours: 2)), 110),
      _program('En ce moment', now.subtract(const Duration(minutes: 10)), 60),
      _program('Ce soir', now.add(const Duration(minutes: 50)), 60),
    ];

Future<EpgProgram?> _open(WidgetTester tester, Channel channel) async {
  BoxMemoryBudget.debugTier = BoxRamTier.roomy;
  addTearDown(() => BoxMemoryBudget.debugTier = null);
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DateTime now = DateTime.now();
  EpgProgram? result;
  bool closed = false;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<EpgProgram>(
                MaterialPageRoute<EpgProgram>(
                  builder: (_) => TvChannelGuideScreen(
                    channel: channel,
                    loadPrograms: (_) async => _day(now),
                  ),
                ),
              );
              closed = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  // Renvoie le résultat une fois le guide refermé par le test.
  tester.binding.addPostFrameCallback((_) {});
  _result = () => closed ? result : null;
  _closed = () => closed;
  return null;
}

EpgProgram? Function() _result = () => null;
bool Function() _closed = () => false;

void main() {
  group('ReplayChoice', () {
    final DateTime now = DateTime(2026, 11, 12, 20);
    final EpgProgram past = _program('Passé', now.subtract(const Duration(hours: 2)), 60);
    final EpgProgram live = _program('Direct', now.subtract(const Duration(minutes: 5)), 60);
    final EpgProgram next = _program('Futur', now.add(const Duration(hours: 1)), 60);

    test('seulement une émission terminée, sur une chaîne qui déclare un catch-up', () {
      expect(ReplayChoice.urlFor(_channel(), past, now),
          startsWith('http://tv.invalid:8080/timeshift/user/pass/60/'));
      expect(ReplayChoice.urlFor(_channel(), live, now), isNull);
      expect(ReplayChoice.urlFor(_channel(), next, now), isNull);
      expect(ReplayChoice.urlFor(_channel(catchup: false), past, now), isNull);
    });

    test('fenêtre d’archive du fournisseur respectée', () {
      final EpgProgram old = _program('Vieux', now.subtract(const Duration(days: 3)), 60);
      expect(ReplayChoice.urlFor(_channel(days: 2), old, now), isNull);
      expect(ReplayChoice.urlFor(_channel(days: 7), old, now), isNotNull);
      // Fenêtre inconnue (null ou 0) : on ne bloque pas.
      expect(ReplayChoice.urlFor(_channel(), old, now), isNotNull);
      expect(ReplayChoice.urlFor(_channel(days: 0), old, now), isNotNull);
    });
  });

  testWidgets('pastille REPLAY sur les émissions terminées uniquement, aide adaptée',
      (WidgetTester tester) async {
    await _open(tester, _channel());
    expect(find.text('Journal du matin'), findsOneWidget);
    expect(find.text('Le film'), findsOneWidget);
    // Deux émissions terminées → deux pastilles ; direct et futur : aucune.
    expect(find.byKey(const ValueKey<String>('guide-replay-pill')), findsNWidgets(2));
    expect(find.text('REPLAY'), findsNWidgets(2));
    expect(find.textContaining('OK sur REPLAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chaîne sans catch-up : aucune pastille, aide d’origine',
      (WidgetTester tester) async {
    await _open(tester, _channel(catchup: false));
    expect(find.byKey(const ValueKey<String>('guide-replay-pill')), findsNothing);
    expect(find.textContaining('OK ou Retour : fermer'), findsOneWidget);
  });

  testWidgets('OK sur une émission REPLAY rend ce programme au lecteur',
      (WidgetTester tester) async {
    await _open(tester, _channel());
    // Le focus part sur l'émission en cours (ligne 2). Haut → « Le film ».
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_closed(), isTrue);
    expect(_result()?.title, 'Le film');
  });

  testWidgets('OK sur l’émission en cours ferme le guide sans rien relancer',
      (WidgetTester tester) async {
    await _open(tester, _channel());
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_closed(), isTrue);
    expect(_result(), isNull);
  });
}
