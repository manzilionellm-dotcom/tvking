import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/theme/app_theme.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/gold_trial_backend.dart';
import 'package:tv_king/features/subscription/data/gold_trial_controller.dart';
import 'package:tv_king/features/subscription/presentation/gold_trial_card.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  GoldTrialController create(int status, String body, {Completer<http.Response>? pending, bool customer=false}) =>
      GoldTrialController(
        trialRequestsEnabled: true,
        backend: GoldTrialBackend(clientFactory: () => MockClient((_) async {
          if (pending != null) return await pending.future;
          return http.Response(body, status);
        })),
        sourceHeaders: () async => <String, String>{'X-Device-Secret': 'fixture'},
      loadIdentity: () async => const GoldTrialIdentity(mac:'MK:11:22:33:44:55', androidId:'test', appVersion:'1'),
        hasSubscription: () => customer,
        hasLoadedTrial: () => true,
        loadPlaylists: () async => const <Playlist>[],
        playlistChanges: const Stream<List<Playlist>>.empty(),
      );

  Future<void> show(WidgetTester tester, GoldTrialController controller) async {
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.cinema,
      home: Scaffold(body: SingleChildScrollView(child: GoldTrialCard(controller: controller)))));
    await tester.pumpAndSettle();
  }

  testWidgets('offre fermée par défaut : carte invisible, zéro réseau et aucun loader', (tester) async {
    int posts = 0;
    int proofs = 0;
    // Aucun paramètre d'ouverture : c'est la configuration réelle de l'APK.
    final controller = GoldTrialController(
      backend: GoldTrialBackend(clientFactory: () => MockClient((_) async {
        posts++;
        return http.Response('{}', 500);
      })),
      sourceHeaders: () async { proofs++; return <String, String>{}; },
      loadIdentity: () async => const GoldTrialIdentity(
          mac: 'MK:11:22:33:44:55', androidId: 'test', appVersion: '1'),
      hasSubscription: () => false,
      loadPlaylists: () async => const <Playlist>[],
      playlistChanges: const Stream<List<Playlist>>.empty(),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);
    expect(find.text('Je teste'), findsNothing);
    expect(find.text('Essai bientôt disponible'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    await controller.request();
    await tester.pump(const Duration(seconds: 35));
    expect(controller.busy, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(posts, 0);
    expect(proofs, 0);
  });

  testWidgets('ancien serveur OFF : nouveau message et aucun second appel', (tester) async {
    int posts = 0;
    final controller = GoldTrialController(
      trialRequestsEnabled: true,
      backend: GoldTrialBackend(clientFactory: () => MockClient((_) async {
        posts++;
        return http.Response('{"error":"trial_disabled","message":"Les essais sont fermés pour le moment."}', 403);
      })),
      sourceHeaders: () async => <String, String>{},
      loadIdentity: () async => const GoldTrialIdentity(
          mac: 'MK:11:22:33:44:55', androidId: 'test', appVersion: '1'),
      hasSubscription: () => false,
      loadPlaylists: () async => const <Playlist>[],
      playlistChanges: const Stream<List<Playlist>>.empty(),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.tap(find.text('Je teste'));
    await tester.pumpAndSettle();
    expect(find.text('Essai bientôt disponible'), findsOneWidget);
    expect(find.text('Les essais sont fermés pour le moment.'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await controller.request();
    expect(controller.busy, isFalse);
    expect(posts, 1);
  });

  testWidgets('chargement exact et bouton réellement désactivé', (tester) async {
    final Completer<http.Response> pending=Completer<http.Response>();
    final GoldTrialController controller=create(500, '{}', pending:pending);
    addTearDown(controller.dispose);
    await show(tester,controller);
    await tester.tap(find.text('Je teste')); await tester.pump();
    expect(find.text('Activation de votre essai…'), findsOneWidget);
    final FilledButton button=tester.widget(find.byType(FilledButton));
    expect(button.onPressed,isNull);
    pending.complete(http.Response('{}',500)); await tester.pumpAndSettle();
    expect(find.text('Erreur, réessaie.'),findsOneWidget);
    expect(find.text('Je teste'),findsOneWidget);
  });

  for (final (int status, String code, String text, bool whatsapp) in <(int, String, String, bool)>[
    (409,'trial_already_used','Vous avez déjà utilisé votre essai gratuit',true),
    (409,'in_progress','Activation en cours, patiente quelques secondes.',false),
    (403,'trial_disabled','Essai bientôt disponible',true),
    (429,'daily_cap_reached',"Plus d'essais disponibles aujourd'hui, reviens demain.",true),
    (429,'rate_limited','Trop de demandes. Patientez une minute avant de réessayer.',false),
    (500,'private-provider','Erreur, réessaie.',false),
  ]) {
    testWidgets('$code : texte demandé et WhatsApp, aucune donnée fournisseur', (tester) async {
      final GoldTrialController controller=create(status,'{"error":"$code","message":"private-provider-secret"}');
      addTearDown(controller.dispose);
      await show(tester,controller);
      await tester.tap(find.text('Je teste')); await tester.pumpAndSettle();
      expect(find.text(text),findsOneWidget);
      expect(find.text('S’abonner sur WhatsApp'), whatsapp?findsOneWidget:findsNothing);
      expect(find.textContaining('private-provider'),findsNothing);
      expect(GoldTrialCard.whatsapp.toString(),'https://wa.me/447307410512');
    });
  }

  testWidgets('succès : confirmation et date ; déjà client : carte cachée', (tester) async {
    final GoldTrialController controller=create(201,'{"ok":true,"expire":"2026-10-27T12:00:00Z"}');
    addTearDown(controller.dispose);
    await show(tester,controller);
    await tester.tap(find.text('Je teste')); await tester.pumpAndSettle();
    expect(find.text('Essai activé ✔'),findsOneWidget);
    expect(find.textContaining('27/10/2026'),findsOneWidget);
    expect(find.text('Je teste'),findsNothing);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final GoldTrialController customer=create(409,'{"error":"already_customer"}');
    addTearDown(customer.dispose);
    await show(tester,customer);
    await tester.tap(find.text('Je teste')); await tester.pumpAndSettle();
    expect(find.byType(FilledButton),findsNothing);
  });

  testWidgets('abonné : aucun bouton Je teste', (tester) async {
    final GoldTrialController controller=create(500,'{}',customer:true);
    addTearDown(controller.dispose); await show(tester,controller);
    expect(find.text('Je teste'),findsNothing);
  });

  testWidgets('abonnement importé après 403 : toute la carte disparaît immédiatement', (tester) async {
    final StreamController<List<Playlist>> events = StreamController<List<Playlist>>.broadcast();
    int posts = 0;
    final GoldTrialController controller = GoldTrialController(
      trialRequestsEnabled: true,
      backend: GoldTrialBackend(clientFactory: () => MockClient((_) async {
        posts++;
        return http.Response('{"error":"trial_disabled"}', 403);
      })),
      sourceHeaders: () async => <String, String>{'X-Device-Secret': 'fixture'},
      loadIdentity: () async => const GoldTrialIdentity(mac:'MK:11:22:33:44:55', androidId:'test', appVersion:'1'),
      hasSubscription: () => false,
      loadPlaylists: () async => const <Playlist>[],
      playlistChanges: events.stream,
    );
    addTearDown(() async { controller.dispose(); await events.close(); });
    await show(tester, controller);
    await tester.tap(find.text('Je teste'));
    await tester.pumpAndSettle();
    expect(find.text('Essai bientôt disponible'), findsOneWidget);
    expect(find.text('S’abonner sur WhatsApp'), findsOneWidget);
    events.add(<Playlist>[const Playlist(
      id: 1, name: 'Mon abonnement', type: PlaylistType.xtream, createdAt: 1,
    )]);
    await tester.pumpAndSettle();
    expect(find.text('Je teste'), findsNothing);
    expect(find.text('Essai bientôt disponible'), findsNothing);
    expect(find.text('S’abonner sur WhatsApp'), findsNothing);
    await controller.request();
    expect(posts, 1);
  });
}
