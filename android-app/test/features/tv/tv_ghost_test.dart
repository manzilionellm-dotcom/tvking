import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/core/theme/app_colors.dart';
import 'package:tv_king/features/tv/core/tv_ambient.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_comfort.dart';
import 'package:tv_king/features/tv/core/tv_ghost.dart';
import 'package:tv_king/features/tv/core/tv_look.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_starfield.dart';

void main() {
  test('Ghost est plus profond que le confort et le chrome se lit', () {
    const TvAppTokens ghost = TvAppTokens(ghost: true);
    const TvAppTokens comfort = TvAppTokens();
    expect(ghost.bg, TvGhost.bg);
    expect(comfort.bg, isNot(equals(TvGhost.bg)));
    expect(
      TvAppTokens.contrast(ghost.accent, ghost.bg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      TvAppTokens.contrast(ghost.text, ghost.bg),
      greaterThanOrEqualTo(7),
    );
    expect(
      TvAppTokens.contrast(ghost.onAccent, ghost.accent),
      greaterThanOrEqualTo(4.5),
    );
    expect(ghost.bg, isNot(equals(const Color(0xFF121212))));
    expect(comfort.accent, TvTokens.accent);
  });

  test('le reflet dure moins de 300 ms et se tait à 2 Go', () {
    expect(TvGhost.shine.inMilliseconds, lessThan(300));
    expect(TvGhost.pulse.inMilliseconds, lessThan(300));
    expect(BoxMemoryBudget.classify(totalMb: 2048, lowRam: false),
        BoxRamTier.balanced);
    expect(BoxMemoryBudget.classify(totalMb: 3072, lowRam: false),
        BoxRamTier.roomy);
    BoxMemoryBudget.debugTier = BoxRamTier.balanced;
    expect(BoxMemoryBudget.paintFocusGlow, isFalse);
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    expect(BoxMemoryBudget.paintFocusGlow, isTrue);
    BoxMemoryBudget.debugTier = null;
  });

  test('le choix Confort reste disponible', () {
    final TvLook look = TvLook.instance;
    look.debugChoose(TvLookChoice.comfort);
    expect(look.ghost, isFalse);
    look.debugChoose(TvLookChoice.ghost);
    expect(look.ghost, isTrue);
    look.debugChoose(TvLookChoice.comfort);
    expect(TvComfortPalette.of(TvComfortPeriod.evening).bg,
        isNot(equals(TvGhost.bg)));
  });

  testWidgets('le reflet traverse la carte en moins de 300 ms',
      (WidgetTester tester) async {
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    addTearDown(() => BoxMemoryBudget.debugTier = null);
    tester.view.physicalSize = const Size(480, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[
            TvAppTokens(ghost: true),
          ],
        ),
        home: const Scaffold(
          backgroundColor: TvGhost.bg,
          body: Center(
            child: RepaintBoundary(
              key: Key('card'),
              child: SizedBox(
                width: 280,
                height: 160,
                child: TvFocusable(
                  autofocus: true,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(TvGhost.shine);
    expect(find.byType(TvFocusable), findsOneWidget);
  });

  test('Phantom Black garde son verre et son fond, le confort les siens', () {
    const TvAppTokens ghost = TvAppTokens(ghost: true);
    const TvAppTokens comfort = TvAppTokens();
    final TvComfortPalette evening =
        TvComfortPalette.of(TvComfortPeriod.evening);
    expect(ghost.glassFill, AppColors.stealthGlass);
    expect(comfort.glassFill, evening.glassFill);
    expect(
      (ghost.bgGradient as RadialGradient).colors,
      <Color>[TvGhost.bg, TvGhost.bg],
    );
    expect(comfort.bgGradient, evening.ambient);
  });

  testWidgets('sous Phantom Black, TvShell ne peint pas le halo du soir',
      (WidgetTester tester) async {
    Future<Gradient?> shellGradient(TvAppTokens palette) async {
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(extensions: <ThemeExtension<dynamic>>[palette]),
          home: const TvShell(child: SizedBox.expand()),
        ),
      );
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TvShell),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).gradient;
    }

    const TvAppTokens ghost = TvAppTokens(ghost: true);
    expect(await shellGradient(ghost), ghost.bgGradient);
    expect(find.byType(PhantomWeave), findsNothing);

    const TvAppTokens comfort = TvAppTokens();
    final TvComfortPalette evening =
        TvComfortPalette.of(TvComfortPeriod.evening);
    expect(
      await shellGradient(comfort),
      TvAmbientLook(peak: evening.ambientPeak, bg: comfort.bg).gradient,
    );
    expect(find.byType(PhantomWeave), findsNothing);
  });
}
