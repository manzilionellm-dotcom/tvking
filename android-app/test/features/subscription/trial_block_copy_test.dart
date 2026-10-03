// Texte de l'écran « essai terminé » : français, anglais, surcharge
// du panel, lien de paiement vide par défaut. Pas de réseau.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/support/vip_support.dart';
import 'package:tv_king/features/subscription/data/trial_block_copy.dart';
import 'package:tv_king/features/subscription/presentation/trial_block_screen.dart';

void main() {
  test('français intégré, anglais intégré, panel, lien vide', () {
    final TrialBlockText fr = resolveTrialBlock(languageCode: 'fr', daysLeft: 3);
    expect(fr.french, isTrue);
    expect(fr.title, kBuiltInTitleFr);
    expect(fr.body, contains('revendeur'));
    expect(fr.daysLabel, 'Essai · 3 j');
    expect(fr.payUrl, isEmpty);
    expect(fr.macLabel, contains('appareil'));

    final TrialBlockText en = resolveTrialBlock(languageCode: 'en', daysLeft: 1);
    expect(en.french, isFalse);
    expect(en.title, kBuiltInTitleEn);
    expect(en.body, contains('reseller'));
    expect(en.daysLabel, 'Trial · 1 d');

    final TrialBlockText custom = resolveTrialBlock(
      languageCode: 'fr',
      titleFr: 'Titre du panel',
      bodyFr: 'Texte du panel',
      payUrl: '',
      daysLeft: 0,
    );
    expect(custom.title, 'Titre du panel');
    expect(custom.body, 'Texte du panel');
    expect(custom.payUrl, isEmpty);

    final TrialBlockText customEn = resolveTrialBlock(
      languageCode: 'en',
      titleEn: 'Panel title',
      bodyEn: 'Panel text',
      payUrl: 'https://exemple.test/payer',
      daysLeft: 0,
    );
    expect(customEn.title, 'Panel title');
    expect(customEn.payUrl, 'https://exemple.test/payer');
  });

  testWidgets('écran : titre, MAC visible, téléphone déjà connu', (WidgetTester tester) async {
    const String mac = 'MK:AB:CD:EF:01:23';
    final TrialBlockText text = resolveTrialBlock(languageCode: 'fr', daysLeft: 0);
    await tester.pumpWidget(MaterialApp(
      home: TrialBlockScreen(mac: mac, text: text),
    ));
    expect(find.text(kBuiltInTitleFr), findsOneWidget);
    expect(find.text(mac), findsOneWidget);
    expect(find.text(VipSupport.displayNumber), findsWidgets);
    expect(find.text('Écrire sur WhatsApp'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
  });
}
