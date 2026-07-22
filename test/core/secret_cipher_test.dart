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

  group('v2 (DEK matérielle) préférée + migration', () {
    test('round-trip v2 : chiffre en enc:v2: et déchiffre', () {
      final SecretCipher c = SecretCipher.instance
        ..debugSetV2KeyForTest(List<int>.generate(32, (int i) => 255 - i));
      const String secret = 'motDePasseXtream_v2';
      final String encd = c.encrypt(secret);
      expect(encd.startsWith('enc:v2:'), isTrue,
          reason: 'la v2 est préférée quand la DEK matérielle est là');
      expect(c.decrypt(encd), secret);
    });

    test('migration : une valeur enc:v1: reste lisible même en mode v2', () {
      // On chiffre d'abord en v1 (comme une install existante), puis on
      // active la v2 : l'ancienne valeur doit encore se déchiffrer.
      final SecretCipher c = SecretCipher.instance;
      c.debugSetKeyForTest(List<int>.generate(32, (int i) => i));
      final String v1Encrypted = c.encrypt('ancienSecret');
      expect(v1Encrypted.startsWith('enc:v1:'), isTrue);
      // La v2 s'active (nouvelle install migrée) mais la v1 reste branchée
      // pour relire l'existant.
      c.debugSetV2KeyForTest(List<int>.generate(32, (int i) => 100 + i));
      expect(c.decrypt(v1Encrypted), 'ancienSecret',
          reason: 'les valeurs v1 doivent survivre à l\'arrivée de la v2');
      // Et le NOUVEAU chiffrement passe bien en v2.
      expect(c.encrypt('nouveauSecret').startsWith('enc:v2:'), isTrue);
    });
  });
}
