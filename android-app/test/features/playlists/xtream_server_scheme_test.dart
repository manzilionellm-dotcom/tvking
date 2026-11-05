import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/presentation/widgets/xtream_login_form.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder serverField() => find.byWidgetPredicate((widget) =>
      widget is TextField && widget.keyboardType == TextInputType.url);

  testWidgets('Xtream : coller et taper http:// ne devient pas https://',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: XtreamLoginForm()),
    ));
    await tester.pump();

    final TextField field = tester.widget<TextField>(serverField());
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.smartDashesType, SmartDashesType.disabled);
    expect(field.smartQuotesType, SmartQuotesType.disabled);
    expect(field.enableIMEPersonalizedLearning, isFalse);

    const pasted = 'http://panel.invalid:8080';
    await tester.enterText(serverField(), pasted);
    expect(tester.widget<TextField>(serverField()).controller!.text, pasted);

    await tester.tap(serverField());
    await tester.pump();
    await tester.showKeyboard(serverField());
    const typed = 'https://autre.invalid';
    final buffer = StringBuffer();
    for (final int code in typed.codeUnits) {
      buffer.writeCharCode(code);
      final String soFar = buffer.toString();
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: soFar,
        selection: TextSelection.collapsed(offset: soFar.length),
      ));
      await tester.pump();
      expect(tester.widget<TextField>(serverField()).controller!.text, soFar);
    }
  });
}
