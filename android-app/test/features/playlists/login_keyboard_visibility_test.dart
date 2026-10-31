import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/presentation/m3u_login_sheet.dart';
import 'package:tv_king/features/playlists/presentation/xtream_login_sheet.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  Future<void> openOnSmallPhone(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () => open(context),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('Xtream : mot de passe visible au-dessus du clavier', (tester) async {
    await openOnSmallPhone(tester, showXtreamLoginSheet);
    final Finder password = find.byType(TextField).last;
    expect(password, findsOneWidget);
    await tester.ensureVisible(password);
    await tester.tap(password);
    await tester.pumpAndSettle();

    final double bottom = tester.getBottomLeft(password).dy;
    expect(bottom, lessThanOrEqualTo(640 - 300 + 12),
        reason: 'le champ ne doit pas être masqué par le clavier');
    expect(tester.takeException(), isNull);
  });

  testWidgets('M3U : champ URL accessible avec le clavier', (tester) async {
    await openOnSmallPhone(tester, showM3uLoginSheet);
    final Finder url = find.byType(TextField).first;
    await tester.ensureVisible(url);
    await tester.tap(url);
    await tester.pumpAndSettle();

    final double bottom = tester.getBottomLeft(url).dy;
    expect(bottom, lessThanOrEqualTo(640 - 300 + 12));
    expect(tester.takeException(), isNull);
  });
}
