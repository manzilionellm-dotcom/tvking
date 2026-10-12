// Régression : sans direction explicite, un début numérique de MAC peut
// migrer à droite en arabe. Les données ci-dessous sont entièrement factices.
import 'dart:ui' show TextBox;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/tv/presentation/tv_activation_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _mac = 'MK:12:34:AB:CD:56';
const _display = '12:34:AB:CD:56';

// Mesure les positions des caractères réellement rendus : une comparaison
// des seules chaînes ne détecterait pas ce défaut d'affichage bidirectionnel.
String visualOrder(
  String text,
  List<TextBox> Function(TextSelection) boxesFor,
) {
  final positions = <({double x, int index})>[];
  for (var i = 0; i < text.length; i++) {
    final boxes = boxesFor(TextSelection(baseOffset: i, extentOffset: i + 1));
    expect(boxes, hasLength(1));
    positions.add((x: boxes.single.left, index: i));
  }
  positions.sort((a, b) => a.x.compareTo(b.x));
  return positions.map((p) => text[p.index]).join();
}

Widget app(Widget child, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'device.virtual_mac.v1': _mac});
    RepairFlags.debugReset();
  });

  test('contre-preuve : la direction arabe déplace le début numérique', () {
    final painter = TextPainter(
      text: const TextSpan(text: _display),
      textDirection: TextDirection.rtl,
    )..layout();
    expect(
      visualOrder(_display, painter.getBoxesForSelection),
      'AB:CD:56:12:34',
    );
    painter.dispose();
  });

  testWidgets('en arabe, écran réel, QR et copie gardent la même MAC', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      app(const TvActivationScreen(), const Locale('ar')),
    );
    await tester.pumpAndSettle();
    // Les appels HTTP des widget tests reçoivent 400 ; aucun Worker réel n'est
    // contacté. Le délai couvre aussi le repli du QR « Mon espace ».
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(TvActivationScreen))),
      TextDirection.rtl,
    );
    final richText = find.descendant(
      of: find.text(_display),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    expect(visualOrder(_display, paragraph.getBoxesForSelection), _display);

    final qr = tester
        .widgetList<QrImageView>(find.byType(QrImageView))
        .toList();
    final whatsapp = Uri.parse(
      qr.singleWhere((q) => q.data!.startsWith('https://wa.me/')).data!,
    );
    expect(
      whatsapp.queryParameters['text'],
      'مرحبًا، أود تفعيل Zuno.\nMAC: $_display',
    );
    final portal = Uri.parse(
      qr.singleWhere((q) => q.data!.contains('/mon-espace')).data!,
    );
    expect(Uri.splitQueryString(portal.fragment)['mac'], _mac);

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump(const Duration(seconds: 3));
    expect(copied, _display);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('device.virtual_mac.v1'), _mac);
    expect(tester.takeException(), isNull);
    // Libère le minuteur de renouvellement du QR, sans altérer le réseau app.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('le même QR passe anglais → arabe sans changer de destinataire', (
    tester,
  ) async {
    const qr = TvWhatsAppQr(mac: _mac, size: 120);
    await tester.pumpWidget(app(qr, const Locale('en')));
    await tester.pumpAndSettle();
    final first = Uri.parse(
      tester.widget<QrImageView>(find.byType(QrImageView)).data!,
    );
    expect(
      first.queryParameters['text'],
      'Hello, I would like to activate Zuno.\nMAC: $_display',
    );
    await tester.pumpWidget(app(qr, const Locale('ar')));
    await tester.pumpAndSettle();
    final second = Uri.parse(
      tester.widget<QrImageView>(find.byType(QrImageView)).data!,
    );
    expect(second.path, first.path);
    expect(
      second.queryParameters['text'],
      'مرحبًا، أود تفعيل Zuno.\nMAC: $_display',
    );
    expect(tester.takeException(), isNull);
  });

  test('la ligne MAC ASCII reste lisible et copiable dans les deux sens', () {
    for (final direction in TextDirection.values) {
      for (final code in [_display, _mac, '12:34:56:78:90']) {
        final line = 'MAC: $code';
        final painter = TextPainter(
          text: TextSpan(text: line),
          textDirection: direction,
        )..layout();
        expect(visualOrder(line, painter.getBoxesForSelection), line);
        painter.dispose();
      }
    }
  });
}
