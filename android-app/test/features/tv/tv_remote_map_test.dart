import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/core/tv_remote_map.dart';
import 'package:tv_king/features/tv/core/tv_remote_shortcuts.dart';

LogicalKeyboardKey _android(int code) =>
    LogicalKeyboardKey(0x01100000000 | code);

void main() {
  test('D-pad, OK, chiffres, média et touches de box', () {
    expect(
        readTvRemoteKey(LogicalKeyboardKey.arrowUp)!.action, TvRemoteAction.up);
    expect(readTvRemoteKey(LogicalKeyboardKey.arrowDown)!.action,
        TvRemoteAction.down);
    expect(readTvRemoteKey(LogicalKeyboardKey.arrowLeft)!.action,
        TvRemoteAction.left);
    expect(readTvRemoteKey(LogicalKeyboardKey.arrowRight)!.action,
        TvRemoteAction.right);
    expect(readTvRemoteKey(LogicalKeyboardKey.select)!.action,
        TvRemoteAction.select);
    expect(readTvRemoteKey(LogicalKeyboardKey.enter)!.action,
        TvRemoteAction.select);
    expect(readTvRemoteKey(LogicalKeyboardKey.numpadEnter)!.action,
        TvRemoteAction.select);
    expect(readTvRemoteKey(LogicalKeyboardKey.gameButtonA)!.action,
        TvRemoteAction.select);
    expect(
      readTvRemoteKey(LogicalKeyboardKey.gameButtonSelect)!.action,
      TvRemoteAction.select,
    );
    expect(readTvRemoteKey(LogicalKeyboardKey.gameButtonB)!.action,
        TvRemoteAction.back);
    expect(readTvRemoteKey(LogicalKeyboardKey.goBack)!.action,
        TvRemoteAction.back);
    expect(readTvRemoteKey(LogicalKeyboardKey.escape)!.action,
        TvRemoteAction.back);
    expect(readTvRemoteKey(LogicalKeyboardKey.channelUp)!.action,
        TvRemoteAction.channelUp);
    expect(readTvRemoteKey(LogicalKeyboardKey.channelDown)!.action,
        TvRemoteAction.channelDown);
    expect(readTvRemoteKey(LogicalKeyboardKey.pageUp)!.action,
        TvRemoteAction.pageUp);
    expect(readTvRemoteKey(LogicalKeyboardKey.pageDown)!.action,
        TvRemoteAction.pageDown);
    expect(readTvRemoteKey(LogicalKeyboardKey.digit4)!.digit, 4);
    expect(readTvRemoteKey(LogicalKeyboardKey.numpad9)!.digit, 9);
    expect(
      readTvRemoteKey(LogicalKeyboardKey.mediaPlayPause)!.action,
      TvRemoteAction.playPause,
    );
    expect(readTvRemoteKey(LogicalKeyboardKey.mediaRewind)!.action,
        TvRemoteAction.rewind);
    expect(
      readTvRemoteKey(LogicalKeyboardKey.mediaFastForward)!.action,
      TvRemoteAction.fastForward,
    );
    expect(readTvRemoteKey(LogicalKeyboardKey.contextMenu)!.action,
        TvRemoteAction.menu);
    expect(
        readTvRemoteKey(LogicalKeyboardKey.info)!.action, TvRemoteAction.info);
    expect(readTvRemoteKey(LogicalKeyboardKey.guide)!.action,
        TvRemoteAction.guide);

    // Codes bruts Android : infrarouge, Formuler, style MAG.
    expect(readTvRemoteKey(_android(23))!.action, TvRemoteAction.select);
    expect(readTvRemoteKey(_android(160))!.action, TvRemoteAction.select);
    expect(readTvRemoteKey(_android(97))!.action, TvRemoteAction.back);
    expect(readTvRemoteKey(_android(166))!.action, TvRemoteAction.channelUp);
    expect(readTvRemoteKey(_android(172))!.action, TvRemoteAction.guide);
    expect(readTvRemoteKey(_android(165))!.action, TvRemoteAction.info);
    expect(readTvRemoteKey(_android(82))!.action, TvRemoteAction.menu);
    expect(readTvRemoteKey(_android(12))!.digit, 5);
    expect(readTvRemoteKey(_android(89))!.action, TvRemoteAction.rewind);
    expect(readTvRemoteKey(_android(90))!.action, TvRemoteAction.fastForward);
    expect(readTvRemoteKey(_android(9999)), isNull);
  });

  testWidgets('Canal − déplace le focus, le clic souris valide', (
    WidgetTester tester,
  ) async {
    final FocusNode first = FocusNode();
    final FocusNode second = FocusNode();
    int selected = 0;
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvRemoteShortcuts(
          child: Column(
            children: <Widget>[
              TvFocusable(
                focusNode: first,
                autofocus: true,
                onSelect: () => selected = 1,
                child: const Text('un'),
              ),
              TvFocusable(
                focusNode: second,
                onSelect: () => selected = 2,
                child: const Text('deux'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.channelDown);
    await tester.pump();
    expect(second.hasFocus, isTrue);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('un')));
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await tester.pump();
    expect(selected, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
