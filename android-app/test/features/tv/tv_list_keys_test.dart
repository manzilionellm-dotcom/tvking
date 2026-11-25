import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/core/tv_list_keys.dart';
import 'package:tv_king/features/tv/core/tv_remote_shortcuts.dart';

// Même géométrie que l'écran Direct : catégories (46 px) à gauche, chaînes
// (74 px) au centre. Une liste courte laisse des catégories plus bas que la
// dernière chaîne, et une chaîne touche plusieurs catégories en hauteur.
void main() {
  late List<FocusNode> cats;
  late List<FocusNode> channels;

  Future<void> show(
    WidgetTester tester, {
    required int catCount,
    required int channelCount,
    bool Function()? onLeft,
    bool guardEdges = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    cats = List<FocusNode>.generate(
        catCount, (int i) => FocusNode(debugLabel: 'cat$i'));
    channels = List<FocusNode>.generate(
        channelCount, (int i) => FocusNode(debugLabel: 'channel$i'));
    addTearDown(() {
      for (final FocusNode node in <FocusNode>[...cats, ...channels]) {
        node.dispose();
      }
    });

    Widget row(FocusNode node, {required bool last, bool Function()? left}) =>
        TvListRowKeys(
          last: guardEdges && last,
          onLeft: guardEdges ? left : null,
          child: TvFocusable(
            focusNode: node,
            child: const SizedBox.expand(),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: TvRemoteShortcuts(
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 300,
                height: 600,
                child: ListView(
                  itemExtent: 46,
                  children: <Widget>[
                    for (int i = 0; i < catCount; i++)
                      row(cats[i], last: i == catCount - 1),
                  ],
                ),
              ),
              SizedBox(
                width: 400,
                height: 600,
                child: ListView(
                  itemExtent: 74,
                  children: <Widget>[
                    for (int i = 0; i < channelCount; i++)
                      row(channels[i],
                          last: i == channelCount - 1, left: onLeft),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> focus(WidgetTester tester, FocusNode node) async {
    node.requestFocus();
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('géométrie du piège : sans garde, Bas sort de la liste',
      (WidgetTester tester) async {
    await show(tester, catCount: 4, channelCount: 2, guardEdges: false);
    await focus(tester, channels[1]);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(cats[3].hasPrimaryFocus, isTrue);
  });

  for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.channelDown,
  ]) {
    testWidgets('dernière chaîne : ${key.keyLabel} reste dans la liste',
        (WidgetTester tester) async {
      await show(tester, catCount: 4, channelCount: 2);
      await focus(tester, channels[1]);
      await press(tester, key);
      expect(channels[1].hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('dernière catégorie : Bas ne saute pas dans les chaînes',
      (WidgetTester tester) async {
    await show(tester, catCount: 3, channelCount: 4);
    await focus(tester, cats[2]);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(cats[2].hasPrimaryFocus, isTrue);
  });

  testWidgets('les autres flèches gardent leur chemin habituel',
      (WidgetTester tester) async {
    await show(tester, catCount: 4, channelCount: 3);
    await focus(tester, channels[0]);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(channels[1].hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(channels[2].hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(channels[1].hasPrimaryFocus, isTrue);
    await focus(tester, cats[3]);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(cats[2].hasPrimaryFocus, isTrue);
  });

  testWidgets('Gauche va à la catégorie désignée, pas à celle de même hauteur',
      (WidgetTester tester) async {
    int calls = 0;
    await show(tester, catCount: 4, channelCount: 2, onLeft: () {
      calls++;
      cats[0].requestFocus();
      return true;
    });
    await focus(tester, channels[1]);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(calls, 1);
    expect(cats[0].hasPrimaryFocus, isTrue);
  });

  testWidgets('Gauche sans cible : la recherche habituelle reprend',
      (WidgetTester tester) async {
    await show(tester, catCount: 4, channelCount: 2, onLeft: () => false);
    await focus(tester, channels[1]);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(cats[2].hasPrimaryFocus, isTrue);
  });
}
