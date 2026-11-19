import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/panel_board/presentation/panel_button.dart';
import 'package:tv_king/features/panel_board/presentation/tv_panel_notice.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('QR annonce : URL sûre seulement, message et Vu conservés',
      (tester) async {
    Future<void> show(String url) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TvPanelNotice(
            notice: Announcement(
                id: 1,
                title: 'Annonce',
                body: 'Texte conservé',
                url: url,
                kind: '',
                cta: 'Lien du panel',
                createdAt: 0),
            onSeen: () {},
          ),
        ),
      ));
      await tester.pump();
    }

    await show('https://user:secret@fixture.invalid');
    expect(find.text('Texte conservé'), findsOneWidget);
    expect(find.byType(PanelButton), findsOneWidget);
    expect(find.byType(PanelQr), findsNothing);
    expect(find.text('Lien du panel'), findsNothing);
    await show('https://fixture.invalid/contact');
    expect(find.byType(PanelQr), findsOneWidget);
    expect(tester.widget<PanelQr>(find.byType(PanelQr)).data,
        'https://fixture.invalid/contact');
    expect(find.text('Lien du panel'), findsOneWidget);
  });
}
