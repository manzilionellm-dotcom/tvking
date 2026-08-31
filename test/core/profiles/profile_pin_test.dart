// =========================================================
//  profile_pin_test.dart — Le PIN calculé des deux côtés
// =========================================================
//  CE QUE CE TEST PROTÈGE, ET POURQUOI IL EXISTE.
//
//  Le code d'un profil est vérifié dans l'app (Dart) mais CALCULÉ dans le
//  panel (JavaScript, Cloudflare Worker). Deux implémentations, une seule
//  formule. Si elles divergent d'un seul octet — un « = » de remplissage
//  en trop, un ordre d'arguments inversé dans le HMAC — AUCUN PIN n'est
//  jamais accepté, et le symptôme côté client est « mon code ne marche
//  pas », sans la moindre erreur dans les journaux.
//
//  Les empreintes ci-dessous ont été PRODUITES PAR LE WORKER (le vrai
//  code de cloudflare/worker.js, exécuté sous Node avec WebCrypto), puis
//  recopiées ici. Le test échoue donc dès que le côté Dart s'en écarte.
//  Recopier une valeur calculée par Dart n'aurait rien prouvé : les deux
//  côtés auraient été d'accord entre eux, et faux ensemble.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/profiles/profiles_repository.dart';

void main() {
  group('ProfilePin — accord Dart / Worker', () {
    // pin, sel, empreinte attendue (sortie du worker sous Node).
    const List<List<String>> vecteurs = <List<String>>[
      <String>['1234', 'a1b2c3', 'E7wIp8UAB3KKaLeacPgujW1NhywUFRaRE9Kuud9NT5I='],
      <String>[
        '9999',
        'sel-avec-tiret',
        'COUWJgW0GLxc6VCUIoMzVKg-cm5V84R5jWKE8OyKjyE=',
      ],
      <String>[
        '12345678',
        '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f',
        '_ljUokT1imogh0FPUFcfjg8pUvuePxlneP9hc2k9Jcc=',
      ],
    ];

    for (final List<String> v in vecteurs) {
      test('derive("${v[0]}") donne la meme empreinte que le panel', () {
        expect(ProfilePin.derive(v[0], v[1]), v[2]);
      });
    }

    test('matches() accepte le bon code et refuse les autres', () {
      final ProfilePin p =
          ProfilePin(salt: 'a1b2c3', hash: ProfilePin.derive('1234', 'a1b2c3'));
      expect(p.matches('1234'), isTrue);
      expect(p.matches('1235'), isFalse);
      expect(p.matches(''), isFalse);
      // Un code qui commence pareil ne doit pas passer : c'est le cas que
      // rate une comparaison écrite trop vite (préfixe au lieu d'égalité).
      expect(p.matches('12'), isFalse);
      expect(p.matches('12345'), isFalse);
    });

    test('deux sels differents donnent deux empreintes differentes', () {
      // Sans sel, deux enfants ayant choisi « 1234 » auraient la MÊME
      // empreinte : lire celle de l'un révélerait le code de l'autre.
      expect(
        ProfilePin.derive('1234', 'sel-a'),
        isNot(ProfilePin.derive('1234', 'sel-b')),
      );
    });
  });
}
