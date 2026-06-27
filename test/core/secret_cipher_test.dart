// =========================================================
//  secret_cipher_test.dart — Chiffrement des identifiants au repos
// =========================================================
//  Valide le round-trip AES-GCM et la rétro-compatibilité (les anciennes
//  valeurs en clair, sans préfixe, doivent rester lisibles → migration sans
//  perte). Clé injectée via le seam de test (pas de plugin natif en test).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/security/secret_cipher.dart';

void main() {
  final SecretCipher cipher = SecretCipher.instance;
  // Clé déterministe (32 octets) — pas d'ANDROID_ID en environnement de test.
  cipher.debugSetKeyForTest(List<int>.generate(32, (int i) => i));

  test('round-trip : chiffre puis déchiffre à l\'identique', () {
    const String secret = 'motDePasseXtream123!';
    final String encd = cipher.encrypt(secret);
    expect(encd.startsWith('enc:v1:'), isTrue);
    expect(encd == secret, isFalse); // c'est bien chiffré
    expect(cipher.decrypt(encd), secret); // et déchiffrable
  });

  test('valeur en clair héritée (sans préfixe) renvoyée telle quelle', () {
    expect(cipher.decrypt('ancienMotDePasseEnClair'), 'ancienMotDePasseEnClair');
  });

  test('chaîne vide inchangée', () {
    expect(cipher.encrypt(''), '');
  });
}
