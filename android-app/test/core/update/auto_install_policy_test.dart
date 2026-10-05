// =========================================================
//  auto_install_policy_test.dart — Quand la box ouvre-t-elle
//  l'installateur toute seule ?
// =========================================================
//  Demande du propriétaire (05/10/2026) : plus de bouton, la mise à
//  jour se fait d'elle-même. Ce qui reste : la confirmation Android.
//  Règles : jamais pendant une chaîne, jamais sans l'autorisation
//  « applications inconnues », une seule fois par version, et le
//  repli coupe tout.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_service.dart';

void main() {
  test('à l\'accueil, autorisé, jamais proposé : on ouvre l\'installateur', () {
    expect(
      UpdateService.shouldAutoInstall(
        off: false, busy: false, canInstall: true, alreadyPrompted: false,
      ),
      isTrue,
    );
  });

  test('une chaîne joue : on attend', () {
    expect(
      UpdateService.shouldAutoInstall(
        off: false, busy: true, canInstall: true, alreadyPrompted: false,
      ),
      isFalse,
    );
  });

  test('sans autorisation Android : l\'APK reste prêt pour Réglages', () {
    expect(
      UpdateService.shouldAutoInstall(
        off: false, busy: false, canInstall: false, alreadyPrompted: false,
      ),
      isFalse,
    );
  });

  test('déjà proposé pour cette version : pas de fenêtre en boucle', () {
    expect(
      UpdateService.shouldAutoInstall(
        off: false, busy: false, canInstall: true, alreadyPrompted: true,
      ),
      isFalse,
    );
  });

  test('repli zuno.update.auto_install_off : jamais', () {
    expect(
      UpdateService.shouldAutoInstall(
        off: true, busy: false, canInstall: true, alreadyPrompted: false,
      ),
      isFalse,
    );
    expect(UpdateService.autoPromptedKey, 'zuno.update.auto_prompted.v1');
  });
}
