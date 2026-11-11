// Capture opt-in du vrai écran, utilisable SANS changement sur le commit 116.
// Le nom n'est pas *_test.dart : le protocole impose explicitement la minute
// attendue et la destination, puis compare les deux images complètes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';

import 'hub_tick_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const expectedTime = String.fromEnvironment('ZUNO_CAPTURE_TIME');
  const output = String.fromEnvironment('ZUNO_CAPTURE_FILE');
  setUpAll(() async {
    if (expectedTime.isEmpty || output.isEmpty) {
      throw StateError('ZUNO_CAPTURE_TIME et ZUNO_CAPTURE_FILE requis');
    }
    await HubTickFixture.setUpAll();
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null || sdk.isEmpty) throw StateError('FLUTTER_ROOT requis');
    final bytes = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });
  setUp(HubTickFixture.setUp);
  tearDownAll(HubTickFixture.tearDownAll);

  testWidgets('L1-06 capture source : minute affichée imposée $expectedTime',
      (tester) async {
    await http.runWithClient(() async {
      final key = GlobalKey();
      await HubTickFixture.mount(tester,
          child: RepaintBoundary(key: key, child: const TvHubScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(expectedTime), findsOneWidget,
          reason:
              'Une comparaison entre deux minutes différentes est refusée.');
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(output);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });
}
