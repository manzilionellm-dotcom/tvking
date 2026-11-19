// =========================================================
//  tv_vip_polish_test.dart — halo qui suit le rayon, logo posé
// =========================================================
//  Le halo par défaut est 12 dp. Une tuile à 18 dp doit pouvoir
//  demander le même rayon, sinon l'ombre dessine un autre rectangle.
//  Le logo, lui, est déjà à l'échelle 1 quand les animations sont
//  coupées (tests, et box qui demandent moins de mouvement).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_dimens.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('le halo prend le rayon demandé et se tait si le fond or suffit',
      (WidgetTester tester) async {
    const BorderRadius radius = BorderRadius.all(Radius.circular(18));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        home: TvFocusBuilder(
          autofocus: true,
          borderRadius: radius,
          showGlow: false,
          onSelect: () {},
          builder: (BuildContext context, bool focused) => const SizedBox(
            width: 80,
            height: 80,
          ),
        ),
      ),
    );
    await tester.pump();
    final AnimatedContainer box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final BoxDecoration deco = box.decoration! as BoxDecoration;
    expect(deco.borderRadius, radius);
    expect(deco.boxShadow, isNull);
  });

  testWidgets('sans rayon, le halo reste celui des cartes (12)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        home: TvFocusable(
          autofocus: true,
          onSelect: () {},
          child: const SizedBox(width: 40, height: 40),
        ),
      ),
    );
    await tester.pump();
    final AnimatedContainer box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final BoxDecoration deco = box.decoration! as BoxDecoration;
    expect(
      deco.borderRadius,
      BorderRadius.circular(TvDimens.cardRadius),
    );
  });

  testWidgets('logo déjà posé quand les animations sont coupées',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Center(child: TvLogo(width: 120)),
      ),
    );
    await tester.pump();
    final ScaleTransition settle = tester.widget<ScaleTransition>(
      find.byType(ScaleTransition),
    );
    expect(settle.scale.value, 1);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('logo se pose en moins de 180 ms', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        home: const Center(child: TvLogo(width: 120)),
      ),
    );
    await tester.pump();
    final ScaleTransition start = tester.widget<ScaleTransition>(
      find.byType(ScaleTransition),
    );
    expect(start.scale.value, lessThan(1));
    await tester.pump(TvDimens.focusAnim);
    final ScaleTransition end = tester.widget<ScaleTransition>(
      find.byType(ScaleTransition),
    );
    expect(end.scale.value, 1);
  });
}
