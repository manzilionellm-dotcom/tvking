// =========================================================
//  tv_live_preview_test.dart — Aperçu « En direct » : repli logo
// =========================================================
//  Contrat de TvLivePreview (écran « En direct » 3 colonnes) :
//    1. tant que l'aperçu n'a PAS démarré (anti-rebond en cours, puis
//       résolution d'URL en cours), le REPLI LOGO est affiché — jamais de
//       cadre noir vide, et AUCUNE vue vidéo native n'est montée ;
//    2. l'anti-rebond (~600 ms) repart à CHAQUE changement de chaîne :
//       zapper dans la liste n'ouvre aucun flux pour les chaînes traversées ;
//    3. `enabled: false` (plein écran imminent) = aucun démarrage.
//  Le résolveur d'URL est INJECTÉ (aucun réseau/SQLite dans ces tests).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_logo.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';

Channel _channel(String id, String name) => Channel(
      id: id,
      name: name,
      category: 'Généralistes',
      streamUrl: 'http://panel.example/live/u/p/$id.ts',
      isLive: true,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 225, child: child),
        ),
      ),
    );

void main() {
  testWidgets(
      'repli logo (sans vue vidéo) tant que l’aperçu n’a pas démarré, '
      'puis logo + spinner pendant la résolution', (WidgetTester tester) async {
    // Résolveur qui ne répond JAMAIS : l'aperçu reste en « chargement ».
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    int calls = 0;
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1', 'Chaîne Une'),
      resolver: (Channel c) {
        calls++;
        return never.future;
      },
    )));

    // Avant l'anti-rebond (600 ms) : logo seul, pas de spinner, pas de vidéo,
    // et surtout AUCUNE ouverture de flux.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TvChannelLogo), findsOneWidget);
    expect(find.byType(NativeVideoView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(calls, 0);

    // Anti-rebond écoulé : la résolution démarre (1 seul appel), le logo
    // reste affiché avec le petit spinner — toujours aucune vue vidéo tant
    // que l'URL n'est pas résolue.
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    expect(find.byType(TvChannelLogo), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(NativeVideoView), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('l’anti-rebond repart à chaque changement de chaîne',
      (WidgetTester tester) async {
    final List<String> resolved = <String>[];
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    Future<TvPreviewSource> resolver(Channel c) {
      resolved.add(c.id);
      return never.future;
    }

    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1', 'Chaîne Une'),
      resolver: resolver,
    )));
    await tester.pump(const Duration(milliseconds: 400));

    // Focus déplacé AVANT la fin de l'anti-rebond : le compteur repart —
    // la chaîne traversée (c1) n'ouvre RIEN.
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c2', 'Chaîne Deux'),
      resolver: resolver,
    )));
    await tester.pump(const Duration(milliseconds: 400));
    expect(resolved, isEmpty);
    expect(find.byType(TvChannelLogo), findsOneWidget);

    // 600 ms sans bouger sur c2 : SEULE c2 démarre.
    await tester.pump(const Duration(milliseconds: 250));
    expect(resolved, <String>['c2']);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enabled:false (plein écran imminent) = aucun démarrage',
      (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1', 'Chaîne Une'),
      enabled: false,
      resolver: (Channel c) async {
        calls++;
        return const TvPreviewSource(url: 'http://x');
      },
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    expect(find.byType(TvChannelLogo), findsOneWidget);
    expect(find.byType(NativeVideoView), findsNothing);
  });
}
