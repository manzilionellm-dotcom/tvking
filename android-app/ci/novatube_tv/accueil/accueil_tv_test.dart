import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_remote_shortcuts.dart';
import 'package:tv_king/features/tv/core/tv_type.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_novatube_access_code_dialog.dart';
import 'package:tv_king/features/tv/presentation/tv_novatube_welcome_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const mk = 'MK:F8:CA:83:78:18';
const recovery = 'DEMO-FAUX-0000';
const labels = <String, String>{
  'm3u': 'Ajouter une liste M3U',
  'xtream': 'Se connecter avec Xtream Codes',
  'check': 'Vérifier mon accès',
  'code': 'Code d’accès',
};
final output = Directory(
  Platform.environment['NOVA_WELCOME_OUT'] ?? 'build/accueil_tv',
);
const boundary = ValueKey('surface_capture');
Finder control(String id) => id == 'check'
    ? find.byWidgetPredicate((w) => w is TvCtaButton && w.label == labels[id])
    : find.byKey(ValueKey('novatube-welcome-$id'));

String? focusId(WidgetTester tester, List<String> ids) {
  for (final id in ids) {
    final label = find.descendant(
      of: control(id),
      matching: find.text(labels[id]!),
    );
    if (label.evaluate().isNotEmpty && Focus.of(tester.element(label)).hasFocus)
      return id;
  }
  return null;
}

List<double> boxPx(WidgetTester tester, Finder finder, double dpr) {
  final r = tester.getRect(finder);
  return [
    r.left,
    r.top,
    r.right,
    r.bottom,
  ].map((v) => (v * dpr * 10).round() / 10).toList();
}

Future<void> render(
  WidgetTester tester,
  Size size,
  double dpr,
  double scale,
  bool licenseOnly,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  const palette = TvAppTokens();
  final theme = ThemeData(
    colorScheme: ColorScheme.dark(
      surface: palette.card,
      primary: palette.accent,
    ),
    scaffoldBackgroundColor: palette.bg,
    extensions: const [palette],
    useMaterial3: true,
  ).copyWith(textTheme: TvType.material(palette.text));
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        locale: const Locale('fr'),
        theme: theme,
        debugShowCheckedModeBanner: false,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) =>
            TvRemoteShortcuts(child: TvScaledViewport(child: child!)),
        home: TvShell(child: TvNovatubeWelcomeScreen(licenseOnly: licenseOnly)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Force le vrai bitmap de marque à finir son décodage avant les mesures.
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(TvLogo));
    await precacheImage(
      const AssetImage('assets/branding/novatube_tv_wordmark.png'),
      ctx,
    );
  });
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String id, double dpr) async {
  final layer = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundary),
  );
  await tester.runAsync(() async {
    final image = await layer.toImage(pixelRatio: dpr);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${output.path}/$id.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 35));
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await GoogleFonts.pendingFonts([
      for (var weight in [FontWeight.w400, FontWeight.w500, FontWeight.w700])
        GoogleFonts.inter(fontWeight: weight),
      for (var weight in [FontWeight.w400, FontWeight.w600])
        GoogleFonts.jetBrainsMono(fontWeight: weight),
    ]);
    final icon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icon.load();
    output.createSync(recursive: true);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
      NovatubeIdentity.kRawKey: '0123456789AB',
      NovatubeIdentity.kDeviceKeyKey: 'a' * 64,
    });
    NovatubeIdentity.instance.resetForTesting();
    NovatubeAtlas.instance.recoveryCode.value = recovery;
  });
  tearDown(() => NovatubeAtlas.instance.recoveryCode.value = null);
  for (final (width, height, dpr) in [
    (1280, 720, 1.0),
    (1920, 1080, 2.0),
    (3840, 2160, 4.0),
  ]) {
    for (final scale in [1.0, 1.3]) {
      for (final gate in [false, true]) {
        final id = '${gate ? "licence" : "accueil"}-${height}p-x$scale';
        testWidgets(id, (tester) async {
          expect(kNovatubeTv, isTrue);
          final dims = Size(width.toDouble(), height.toDouble());
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await render(tester, dims, dpr, scale, gate);
          final ids = gate ? ['check', 'code'] : labels.keys.toList();
          expect(find.text(mk), findsOneWidget);
          final boxes = {
            for (final key in ids) key: boxPx(tester, control(key), dpr),
            'mk': boxPx(tester, find.text(mk), dpr),
            'logo': boxPx(tester, find.byType(TvLogo), dpr),
          };
          final notice = AppLocalizations.of(
            tester.element(find.byType(TvLogo)),
          ).novatubePlayerNotice;
          boxes['notice'] = boxPx(tester, find.text(notice), dpr);
          final bad = boxes.entries
              .where(
                (b) =>
                    b.value[0] < width * .05 ||
                    b.value[1] < height * .05 ||
                    b.value[2] > width * .95 ||
                    b.value[3] > height * .95,
              )
              .map((e) => e.key)
              .toList();
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          final scrollMax = scroll.maxScrollExtent;
          final offset0 = scroll.pixels;
          final hasRecovery = find
              .textContaining(recovery)
              .evaluate()
              .isNotEmpty;
          final hasRecoveryLabel = find
              .textContaining(
                RegExp('assistance.*revendeur', caseSensitive: false),
              )
              .evaluate()
              .isNotEmpty;
          await capture(tester, id, dpr);
          final focus = [focusId(tester, ids)];
          final focusedBoxes = <String, List<double>>{};
          void measureFocus() {
            final id = focus.last;
            if (id == null) return;
            final transformed = find
                .descendant(
                  of: control(id),
                  matching: find.byType(AnimatedContainer),
                )
                .first;
            focusedBoxes[id] = boxPx(tester, transformed, dpr);
          }

          measureFocus();
          for (final key
              in (gate
                  ? [
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowLeft,
                    ]
                  : [
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowDown,
                      LogicalKeyboardKey.arrowLeft,
                      LogicalKeyboardKey.arrowUp,
                    ])) {
            await press(tester, key);
            focus.add(focusId(tester, ids));
            measureFocus();
            if (focus.last == 'code' &&
                height == 720 &&
                scale == 1.0 &&
                !gate) {
              await capture(tester, 'focus-code-720p', dpr);
            }
          }
          final expectedFocus = gate
              ? ['check', 'code', 'check']
              : ['m3u', 'xtream', 'code', 'check', 'm3u'];
          final actualScale =
              MediaQuery.textScalerOf(tester.element(find.text(mk))).scale(16) /
              16;
          final row = <String, dynamic>{
            'id': id,
            'width': width,
            'height': height,
            'dpr': dpr,
            'textScaleSystem': scale,
            'textScaleEffective': actualScale,
            'locale': 'fr',
            'licenseOnly': gate,
            'rectanglesPx': boxes,
            'outsideSafe5Percent': bad,
            'initialScroll': offset0,
            'maxScrollLogical': scrollMax,
            'hasRecoveryValue': hasRecovery,
            'hasRecoveryLabel': hasRecoveryLabel,
            'mk': mk,
            'focus': focus,
            'focusedPaintBoundsPx': focusedBoxes,
            'expectedFocus': expectedFocus,
          };
          File('${output.path}/$id.json').writeAsStringSync(jsonEncode(row));
          expect(focus, expectedFocus);
          for (final r in focusedBoxes.values) {
            expect(
              r[0] >= width * .05 &&
                  r[1] >= height * .05 &&
                  r[2] <= width * .95 &&
                  r[3] <= height * .95,
              isTrue,
              reason: 'La bordure du bouton sélectionné doit rester dans la zone sûre.',
            );
          }
          if (!gate) {
            expect(boxes['m3u']![1], closeTo(boxes['xtream']![1], .1));
            expect(boxes['m3u']![3], closeTo(boxes['xtream']![3], .1));
          }
          expect(
            bad,
            isEmpty,
            reason:
                'Tout le contenu doit tenir dans 5 % de marge dès l’ouverture.',
          );
          expect(
            hasRecovery || hasRecoveryLabel,
            isFalse,
            reason: 'Code d’assistance caché sur l’accueil.',
          );
          expect(
            scrollMax,
            0,
            reason: 'Aucune action ne doit demander de défilement.',
          );
        }, variant: TargetPlatformVariant.only(TargetPlatform.android));
      }
    }
  }
  for (final target in ['m3u', 'xtream', 'code']) {
    testWidgets('OK télécommande vers $target', (tester) async {
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await render(tester, const Size(1280, 720), 1, 1, false);
      if (target != 'm3u') await press(tester, LogicalKeyboardKey.arrowRight);
      if (target == 'code') await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusId(tester, labels.keys.toList()), target);
      await press(tester, LogicalKeyboardKey.select);
      if (target == 'code') {
        expect(find.byType(TvNovatubeAccessCodeDialog), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          isEmpty,
        );
      } else {
        expect(
          tester
              .widget<TvAddSourceScreen>(find.byType(TvAddSourceScreen))
              .initialMode,
          target == 'm3u' ? OpenEntryMode.m3u : OpenEntryMode.xtream,
        );
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
