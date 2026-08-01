// =========================================================
//  tv_live_preview_unavailable_test.dart — Signal « indisponible »
// =========================================================
//  Photo terrain 2026-08-01 : le héro d'accueil pointait une chaîne
//  morte côté fournisseur → grand cadre inutile. TvLivePreview signale
//  désormais onUnavailable (au plus UNE fois par tentative) pour que
//  l'accueil bascule sur un autre candidat. Contrat testé :
//    1. résolution d'URL impossible → onUnavailable appelé UNE fois,
//       et l'aperçu reste sur le logo (jamais de vue vidéo) ;
//    2. résolution encore EN COURS → aucun signal (pas de faux positif) ;
//    3. zap vers une autre chaîne pendant la résolution → le signal de
//       l'ancienne tentative est abandonné (anti-course).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';

Channel _channel(String id) => Channel(
      id: id,
      name: 'Chaîne $id',
      category: 'Test',
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
  testWidgets('résolution impossible → onUnavailable UNE fois, logo conservé',
      (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1'),
      debounce: const Duration(milliseconds: 50),
      resolver: (Channel c) async => throw Exception('panel KO'),
      onUnavailable: () => calls++,
    )));
    // Anti-rebond (50 ms) + résolution qui échoue.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(calls, 1, reason: 'un échec de résolution = UN signal');
    // Jamais de vue vidéo : le repli logo occupe le cadre.
    expect(find.byType(NativeVideoView), findsNothing);
    // Le signal ne se répète pas tant qu'aucune nouvelle tentative ne part.
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });

  testWidgets('résolution en cours → aucun signal (pas de faux positif)',
      (WidgetTester tester) async {
    int calls = 0;
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1'),
      debounce: const Duration(milliseconds: 50),
      resolver: (Channel c) => never.future,
      onUnavailable: () => calls++,
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 0);
  });

  testWidgets('zap pendant la résolution → signal de l\'ancienne tentative jeté',
      (WidgetTester tester) async {
    int calls = 0;
    final Completer<TvPreviewSource> slow = Completer<TvPreviewSource>();
    Widget preview(Channel ch, TvPreviewResolver resolver) =>
        _host(TvLivePreview(
          key: const ValueKey<String>('preview'),
          channel: ch,
          debounce: const Duration(milliseconds: 50),
          resolver: resolver,
          onUnavailable: () => calls++,
        ));
    // Chaîne 1 : résolution lente (elle échouera APRÈS le zap).
    await tester.pumpWidget(preview(_channel('c1'), (Channel c) => slow.future));
    await tester.pump(const Duration(milliseconds: 80));
    // Zap : chaîne 2, résolution qui n'aboutit jamais (pas de signal).
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    await tester.pumpWidget(preview(_channel('c2'), (Channel c) => never.future));
    // L'échec TARDIF de la chaîne 1 arrive maintenant : session périmée.
    slow.completeError(Exception('trop tard'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 0,
        reason: 'un échec d\'une tentative abandonnée ne doit pas faire '
            'basculer le héro');
  });

  testWidgets('l\'app DIT pourquoi il n\'y a pas d\'image (demande client)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1'),
      debounce: const Duration(milliseconds: 50),
      resolver: (Channel c) async => throw Exception('panel KO'),
    )));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    // Le client ne doit plus deviner si c'est l'app ou son fournisseur.
    expect(find.textContaining('introuvable'), findsOneWidget);
  });
}
