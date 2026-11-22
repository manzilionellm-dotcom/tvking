// Saisie du code : réseau entièrement simulé, aucune licence réelle.
// Vérifie les refus, le verrou anti-double-clic et le collage du code complet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/tv/presentation/tv_novatube_access_code_dialog.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'ahem_fonts.dart';

const String _code = 'NVMAX-01234567-89ABCDEF-01234567-89ABCDEF';
const String _registered =
    '{"ok":true,"status":"inactive","active":false,"playback_allowed":false}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installAhemFonts);
  tearDownAll(removeAhemFonts);
  late List<http.Request> seen;
  late Completer<http.Response> reply;
  bool? accepted;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      NovatubeIdentity.kRawKey: '0123456789AB',
      NovatubeIdentity.kDeviceKeyKey: 'a' * 64,
    });
    NovatubeIdentity.instance.resetForTesting();
    NovatubeAtlas.instance.resetForTesting();
    NovatubeAtlas.baseUrl = 'https://atlas.test';
    seen = <http.Request>[];
    reply = Completer<http.Response>();
    accepted = null;
    NovatubeAtlas.clientFactory = () => MockClient((http.Request request) async {
          seen.add(request);
          if (request.url.path.endsWith('/register')) {
            return http.Response(_registered, 200);
          }
          return reply.future;
        });
  });

  tearDown(() {
    NovatubeAtlas.clientFactory = http.Client.new;
    NovatubeAtlas.instance.resetForTesting();
  });

  Future<void> openDialog(WidgetTester tester, {Size size = const Size(1280, 720)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (BuildContext context) => TextButton(
        onPressed: () async {
          accepted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const TvNovatubeAccessCodeDialog(),
          );
        },
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('un code incomplet reste local et laisse corriger la saisie',
      (WidgetTester tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextFormField), 'NVMAX-INCOMPLET');
    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    expect(find.text('Code invalide. Vérifiez-le et réessayez.'), findsOneWidget);
    expect(seen, isEmpty);
    expect(accepted, isNull);
  });

  testWidgets('un échange en cours ne peut pas être soumis deux fois',
      (WidgetTester tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextFormField), _code.toLowerCase());
    final Finder submit =
        find.byKey(const ValueKey<String>('novatube-access-code-submit'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    expect(seen.where((http.Request request) =>
        request.url.path.endsWith('/redeem')).length, 1);
    expect(find.byType(TvNovatubeAccessCodeDialog), findsOneWidget);
    reply.complete(http.Response('{"ok":true,"redeemed":true}', 200));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    expect(find.byType(TvNovatubeAccessCodeDialog), findsNothing);
  });

  testWidgets('un refus garde le dialogue et masque les détails internes',
      (WidgetTester tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextFormField), _code);
    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    reply.complete(http.Response(
        '{"ok":false,"error":"private_server_detail"}', 403));
    await tester.pumpAndSettle();
    expect(find.text('Code invalide. Vérifiez-le et réessayez.'), findsOneWidget);
    expect(find.textContaining('private_server_detail'), findsNothing);
    expect(accepted, isNull);
    expect(find.byType(TvNovatubeAccessCodeDialog), findsOneWidget);
  });

  testWidgets('le formulaire reste utilisable sur un téléphone en portrait',
      (WidgetTester tester) async {
    await openDialog(tester, size: const Size(390, 844));
    await tester.enterText(find.byType(TextFormField), _code);
    await tester.ensureVisible(find.text('Annuler'));
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(seen, isEmpty);
    expect(find.byType(TvNovatubeAccessCodeDialog), findsNothing);
  });
}
