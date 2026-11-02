import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/simple_home/presentation/widgets/announcement_banner.dart';
import 'package:tv_king/features/simple_home/presentation/widgets/announcement_refresh.dart';

Map<String, Object> notice({
  String url = '',
  String cta = '',
  int expires = 0,
}) => <String, Object>{
  'id': 41,
  'title': 'Annonce du panel',
  'body': 'Message',
  'kind': 'info',
  'url': url,
  'cta': cta,
  'expires_at': expires,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AnnouncementRepository.resetForTesting();
    AnnouncementRepository.baseUrl = 'https://fixture.invalid';
  });
  tearDown(AnnouncementRepository.resetForTesting);

  test(
    'le changement de lien et CTA est diffusé, sans nouvel identifiant',
    () async {
      var payload = notice(url: 'https://fixture.invalid/one', cta: 'Ancien');
      AnnouncementRepository.client = MockClient(
        (_) async => http.Response(jsonEncode(payload), 200),
      );
      await AnnouncementRepository.fetchLatest();
      payload = notice(url: 'https://fixture.invalid/two', cta: 'Nouveau');
      await AnnouncementRepository.fetchLatest();
      expect(AnnouncementRepository.latest.value?.url, endsWith('/two'));
      expect(AnnouncementRepository.latest.value?.cta, 'Nouveau');
    },
  );

  test(
    'panne ou réponse malformée conserve, réponse vide 200 retire',
    () async {
      var response = http.Response(jsonEncode(notice()), 200);
      AnnouncementRepository.client = MockClient((_) async => response);
      await AnnouncementRepository.fetchLatest();
      for (final next in <http.Response>[
        http.Response('{}', 503),
        http.Response('HTML', 200),
        http.Response('{"error":"bad"}', 200),
      ]) {
        response = next;
        await expectLater(
          AnnouncementRepository.fetchLatest(strict: true),
          throwsA(anything),
        );
        await AnnouncementRepository.fetchLatest();
        expect(AnnouncementRepository.latest.value?.id, 41);
      }
      response = http.Response('{}', 200);
      await AnnouncementRepository.fetchLatest();
      expect(AnnouncementRepository.latest.value, isNull);
    },
  );

  test('le signal et le poll partagent une seule requête', () async {
    final completer = Completer<http.Response>();
    var calls = 0;
    AnnouncementRepository.client = MockClient((_) {
      calls++;
      return completer.future;
    });
    final first = AnnouncementRepository.fetchLatest();
    final second = AnnouncementRepository.fetchLatest();
    completer.complete(http.Response(jsonEncode(notice()), 200));
    await Future.wait(<Future<Announcement?>>[first, second]);
    expect(calls, 1);
  });

  test(
    'un poll UI simultané ne transforme pas l’échec strict en succès',
    () async {
      final completer = Completer<http.Response>();
      var calls = 0;
      AnnouncementRepository.client = MockClient((_) {
        calls++;
        return completer.future;
      });
      final ui = AnnouncementRepository.fetchLatest();
      final strict = expectLater(
        AnnouncementRepository.fetchLatest(strict: true),
        throwsStateError,
      );
      completer.complete(http.Response('indisponible', 503));
      await strict;
      expect(await ui, isNull);
      expect(calls, 1);
    },
  );

  testWidgets('l’expiration retire aussi sans réseau et sans signal', (
    tester,
  ) async {
    AnnouncementRepository.client = MockClient(
      (_) async => http.Response(
        jsonEncode(
          notice(
            expires: DateTime.now()
                .add(const Duration(seconds: 1))
                .millisecondsSinceEpoch,
          ),
        ),
        200,
      ),
    );
    await AnnouncementRepository.fetchLatest();
    expect(AnnouncementRepository.latest.value, isNotNull);
    await tester.pump(const Duration(seconds: 2));
    expect(AnnouncementRepository.latest.value, isNull);
  });

  testWidgets('le bandeau mobile disparaît quand le panel retire son annonce', (
    tester,
  ) async {
    var response = http.Response(jsonEncode(notice()), 200);
    AnnouncementRepository.client = MockClient((_) async => response);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AnnouncementBanner())),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Annonce du panel'), findsOneWidget);
    response = http.Response('{}', 200);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Annonce du panel'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repli arrêté en arrière-plan, désactivé ou après démontage', (
    tester,
  ) async {
    var calls = 0;
    AnnouncementRepository.client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      const MaterialApp(home: AnnouncementRefresh(child: Text('Accueil'))),
    );
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 3);
    await tester.pumpWidget(
      const MaterialApp(
        home: AnnouncementRefresh(enabled: false, child: Text('Accueil')),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 3);
  });
}
