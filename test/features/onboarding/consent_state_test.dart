// =========================================================
//  consent_state_test.dart — Porte de consentement (CGU)
// =========================================================
//  Sémantique portée de TV King (tests/consent.test.ts) :
//    - rien de stocké → pas accepté ;
//    - version stockée >= version courante → accepté ;
//    - version stockée < version courante → ré-acceptation forcée.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/onboarding/data/consent_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rien de stocké → pas accepté', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await ConsentState.instance.hasAccepted(), isFalse);
  });

  test('markAccepted persiste puis hasAccepted répond vrai', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ConsentState.instance.markAccepted();
    expect(await ConsentState.instance.hasAccepted(), isTrue);
  });

  test('version stockée supérieure → toujours accepté', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'legal.consent.v1': ConsentState.termsVersion + 1,
    });
    expect(await ConsentState.instance.hasAccepted(), isTrue);
  });

  test('version stockée inférieure → ré-acceptation forcée', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'legal.consent.v1': ConsentState.termsVersion - 1,
    });
    expect(await ConsentState.instance.hasAccepted(), isFalse);
  });

  test('reset efface le consentement', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ConsentState.instance.markAccepted();
    await ConsentState.instance.reset();
    expect(await ConsentState.instance.hasAccepted(), isFalse);
  });
}
