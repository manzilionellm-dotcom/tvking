// Capture la galerie typographique avec les vraies fontes embarquées.
// Le fichier PNG est écrit seulement si TYPE_GALLERY_PNG est défini :
// les tests ordinaires ne dépendent pas d'un disque d'artefacts.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/core/theme/bundled_fonts.dart';
import 'package:tv_king/dev/type_gallery.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la galerie tient dans le canevas 1280×720', (tester) async {
    configureTvFontLoading();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        home: const Scaffold(
          body: RepaintBoundary(
            key: Key('type-gallery'),
            child: TypeGallery(),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await GoogleFonts.pendingFonts();
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Ce soir'), findsOneWidget);
    expect(find.text('Cette rangée est encore vide'), findsOneWidget);

    final String? out = Platform.environment['TYPE_GALLERY_PNG'];
    if (out == null || out.isEmpty) return;
    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const Key('type-gallery')),
    );
    final ui.Image? image = await tester.runAsync<ui.Image>(
      () => boundary.toImage(pixelRatio: 1),
    );
    final ByteData? data = await tester.runAsync<ByteData?>(() async {
      return image!.toByteData(format: ui.ImageByteFormat.png);
    });
    expect(data, isNotNull);
    File(out).writeAsBytesSync(data!.buffer.asUint8List());
  });
}
