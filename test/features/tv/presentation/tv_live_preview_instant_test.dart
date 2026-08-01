// =========================================================
//  tv_live_preview_instant_test.dart — Aperçu INSTANTANÉ + passation
// =========================================================
//  DEMANDE CLIENT (2026-08-01) : « une seconde, c'est beaucoup — ça doit
//  être instantané » (grand aperçu du héro), et « en changeant de
//  template, tout doit s'arrêter d'abord ».
//
//  Contrat vérifié ici, dans les conditions réelles des écrans :
//    1. héro (chaîne FIXE, debounce zéro) → la résolution du flux part
//       DANS LA MÊME FRAME, sans attendre d'anti-rebond ;
//    2. liste (chaîne qui défile sous le focus) → l'anti-rebond protège
//       toujours : rien n'est ouvert pour les chaînes traversées ;
//    3. un autre écran possédait le créneau → l'ouverture attend la
//       passation (le décodeur sortant est rendu d'abord), puis part.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/data/tv_preview_arbiter.dart';
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
  tearDown(() {
    // Le créneau est un singleton : on le rend entre deux tests.
    final Object? owner = TvPreviewArbiter.instance.owner;
    if (owner != null) TvPreviewArbiter.instance.release(owner);
  });

  testWidgets('héro (debounce zéro) : le flux part DANS LA MÊME FRAME',
      (WidgetTester tester) async {
    int calls = 0;
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('hero'),
      debounce: Duration.zero,
      resolver: (Channel c) {
        calls++;
        return never.future;
      },
    )));
    // AUCUN pump supplémentaire, AUCUN temps écoulé : le premier build a
    // suffi. (Avant : 600 ms d'attente, 1200 ms sur petite box.)
    expect(calls, 1,
        reason: 'la chaîne du héro est fixe : rien ne justifie d\'attendre');
  });

  testWidgets('liste : l\'anti-rebond protège toujours les chaînes traversées',
      (WidgetTester tester) async {
    int calls = 0;
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1'),
      debounce: const Duration(milliseconds: 600),
      resolver: (Channel c) {
        calls++;
        return never.future;
      },
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 0, reason: 'on défile encore → aucune connexion ouverte');
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1, reason: 'le focus s\'est posé → on ouvre');
  });

  testWidgets('changement de template : on attend que l\'ancien ait rendu '
      'son décodeur, puis on ouvre', (WidgetTester tester) async {
    // Un AUTRE écran (template précédent) possède le créneau.
    final Object ancienTemplate = Object();
    TvPreviewArbiter.instance.acquire(ancienTemplate);

    int calls = 0;
    final Completer<TvPreviewSource> never = Completer<TvPreviewSource>();
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('hero'),
      debounce: Duration.zero,
      resolver: (Channel c) {
        calls++;
        return never.future;
      },
    )));
    // Le créneau a changé de main tout de suite (l'ancien est prévenu)…
    expect(TvPreviewArbiter.instance.holds(ancienTemplate), isFalse);
    // …mais on n'ouvre PAS encore : deux décodeurs ne doivent pas coexister.
    expect(calls, 0);

    await tester.pump(TvPreviewArbiter.handover);
    expect(calls, 1, reason: 'passation terminée → le nouveau template ouvre');
  });
}
