import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/default_servers.dart';
import 'package:tv_king/features/playlists/presentation/widgets/configured_servers_picker.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DefaultServersApi.resetForTesting();
  });

  const valid = <String, Object>{
    'id': '1',
    'label': 'Studio',
    'url': 'https://studio.invalid:8080'
  };

  test('catalogue explicite, adresses sûres et suppression réelle', () async {
    var rows = <Object>[
      valid,
      <String, Object>{...valid, 'id': '2', 'url': 'javascript:bad'},
      <String, Object>{
        ...valid,
        'id': '3',
        'url': 'https://user:pass@studio.invalid'
      },
      <String, Object>{...valid, 'id': '4', 'enabled': false},
      <String, Object>{
        ...valid,
        'id': '5',
        'url': 'https://studio.invalid?password=secret'
      },
      valid,
    ];
    await http.runWithClient(() async {
      expect((await DefaultServersApi.fetch(strict: true)).map((s) => s.id),
          ['1']);
      rows = [];
      await DefaultServersApi.fetch(strict: true);
      expect(DefaultServersApi.current.value, isEmpty);
      expect(await DefaultServersApi.fetch(), isEmpty);
    },
        () => MockClient((request) async {
              expect(request.url.path, '/api/servers');
              return http.Response(jsonEncode({'servers': rows}), 200);
            }));
  });

  test('ordre strict relit après le poll UI et ne masque pas le nouvel échec', () async {
    final reply = Completer<http.Response>();
    var calls = 0;
    await http.runWithClient(() async {
      final ui = DefaultServersApi.fetch(forceRefresh: true);
      final strict =
          expectLater(DefaultServersApi.fetch(strict: true), throwsStateError);
      reply.complete(http.Response('indisponible', 503));
      expect(await ui, isEmpty);
      await strict;
      expect(calls, 2);
    },
        () => MockClient((_) {
              calls++;
              return reply.future;
            }));
  });

  testWidgets(
      'choix volontaire remplit l’URL ; retrait ne détruit pas la saisie',
      (tester) async {
    final controller = TextEditingController(text: 'http://manuel.invalid');
    addTearDown(controller.dispose);
    var rows = <Object>[valid];
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: Column(children: [
          ConfiguredServersPicker(serverController: controller),
          TextField(controller: controller),
        ])),
      ));
      await tester.pumpAndSettle();
      expect(controller.text, 'http://manuel.invalid',
          reason: 'aucune connexion ni sélection automatique');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Studio').last);
      await tester.pumpAndSettle();
      expect(controller.text, 'https://studio.invalid:8080');
      expect(find.text('https://studio.invalid:8080'), findsOneWidget);

      rows = [];
      await DefaultServersApi.fetch(strict: true);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(controller.text, 'https://studio.invalid:8080',
          reason: 'le panel modifie les suggestions, pas la saisie du client');
    },
        () => MockClient(
            (_) async => http.Response(jsonEncode({'servers': rows}), 200)));
  });

  testWidgets('catalogue absent : le champ manuel reste seul', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConfiguredServersPicker(serverController: controller)),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
