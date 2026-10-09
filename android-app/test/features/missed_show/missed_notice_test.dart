import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/missed_show/domain/missed_summary.dart';
import 'package:tv_king/features/missed_show/presentation/missed_notice.dart';

void main() {
  testWidgets('le bandeau libère l’image après deux secondes', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      home: Align(
        alignment: Alignment.topCenter,
        child: MissedNotice(
          summary: MissedSummary(
            title: 'Programme de test',
            missedMinutes: 19,
            description: 'Résumé détaillé du programme.',
          ),
        ),
      ),
    ));
    final Finder noticeText = find.descendant(
      of: find.byType(MissedNotice),
      matching: find.byType(Text),
    );
    expect(noticeText, findsWidgets);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(noticeText, findsWidgets);
    await tester.pump(const Duration(milliseconds: 1));
    expect(noticeText, findsNothing,
        reason: 'le bandeau ne doit plus recouvrir le direct après 2 s');
  });
}
