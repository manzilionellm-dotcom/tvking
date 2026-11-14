import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/presentation/cast_mini_bar.dart';
import 'package:tv_king/features/tv/desktop/desktop_shell.dart';

void main() {
  testWidgets('desktop keeps existing content and global Cast controls mounted',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DesktopCastOverlay(child: Scaffold(body: Text('ZUNO')))));
    expect(find.text('ZUNO'), findsOneWidget);
    expect(find.byType(CastMiniBar), findsOneWidget);
    // Aucune session : aucun bandeau ni icône superposée au design existant.
    expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
  });
}
