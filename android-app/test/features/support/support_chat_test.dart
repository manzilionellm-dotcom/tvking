// Vérifie les gestes réels : pas d’ouverture spontanée, clavier et reprise.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/support/data/support_repository.dart';
import 'package:tv_king/features/support/presentation/support_chat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:CC:11:22:33:44',
    });
  });
  testWidgets('bulle discrète : toucher, écrire, reprise et fermeture', (
    WidgetTester t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
    final SupportRepository repo = SupportRepository(
      client: MockClient((http.Request r) async {
        if (r.method == 'POST') {
          sent.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (sent.length == 1) return http.Response('{}', 503);
          return http.Response('{}', 201);
        }
        return http.Response(
          '{"items":[],"unread":0,"more":false,"owner_read_seq":0}',
          200,
        );
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('Accueil'),
          floatingActionButton: SupportBubble(repository: repo),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(SupportChat), findsNothing);
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.byType(SupportChat), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Bonjour');
    await t.tap(find.byTooltip('Envoyer'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Bonjour',
    );
    await t.tap(find.byTooltip('Envoyer'));
    await t.pumpAndSettle();
    expect(sent.length, 2);
    expect(sent[0]['client_id'], sent[1]['client_id']);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pumpAndSettle();
    expect(find.byType(SupportChat), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('petit téléphone avec clavier : aucune zone ne déborde', (
    WidgetTester t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    final SupportRepository repo = SupportRepository(
      client: MockClient(
        (_) async => http.Response('{"items":[],"unread":0,"more":false}', 200),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(floatingActionButton: SupportBubble(repository: repo)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    t.view.viewInsets = FakeViewPadding(bottom: 280);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byTooltip('Envoyer'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
