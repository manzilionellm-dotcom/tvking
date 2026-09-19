// =========================================================
//  assistance_miroir_test.dart — la taille de l'image envoyée
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « ça pointe bien, mais je
//  vois rien côté admin. »
//
//  La capture elle-même a besoin d'un vrai moteur graphique ; ce qui
//  se teste ici, c'est le CALCUL qui décide du poids de chaque image.
//  Et c'est lui qui coûte cher si on se trompe : une box envoie une
//  image toutes les deux secondes, sur la connexion d'un client qui
//  regarde la télé en même temps.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/assistance/assistance_miroir.dart';

void main() {
  group('la taille de l\'image', () {
    test('une télé est réduite, et beaucoup', () {
      // 1920 points de large → on vise 420. Envoyer du 1920 toutes les
      // deux secondes coûterait 8 fois plus cher pour une information
      // que le support n'utilise pas : il cherche un bouton, il ne lit
      // pas les sous-titres.
      expect(ratioMiroir(1920), closeTo(420 / 1920, 0.0001));
      expect(1920 * ratioMiroir(1920), closeTo(420, 0.5));
    });

    test('un téléphone étroit N\'EST JAMAIS AGRANDI', () {
      //  LE PIÈGE : 420 / 360 fait 1,17. Sans plafond, on demanderait
      //  au moteur graphique de fabriquer des pixels qui n'existent
      //  pas — plus d'octets à transporter, pas un détail de plus à
      //  voir. Le plafond à 1 est donc une économie, pas une limite.
      expect(ratioMiroir(360), 1);
      expect(ratioMiroir(419), 1);
      expect(ratioMiroir(420), 1);
    });

    test('juste au-dessus du seuil, ça réduit déjà', () {
      expect(ratioMiroir(421), lessThan(1));
    });

    test('une largeur absurde ne fait pas tomber la session', () {
      //  Une image à la mauvaise taille reste utile ; une exception au
      //  milieu d'une assistance, non — le client verrait son app se
      //  figer pile au moment où on lui dit « ne bougez pas ».
      for (final double mauvaise in <double>[
        0, -100, double.nan, double.infinity,
      ]) {
        expect(ratioMiroir(mauvaise), 1, reason: '$mauvaise');
      }
    });

    test('une largeur maximale absurde ne casse rien non plus', () {
      expect(ratioMiroir(1920, largeurMax: 0), 1);
      expect(ratioMiroir(1920, largeurMax: double.nan), 1);
    });
  });

  group('les réglages tiennent ensemble', () {
    test('l\'app jette avant que le hub ne refuse', () {
      //  Le hub accepte 128 Ko ; l'app jette au-delà de 90 Ko. L'écart
      //  n'est pas décoratif : il faut que l'app s'arrête D'ELLE-MÊME
      //  avant le mur, sinon elle dépense l'encodage ET la montée
      //  réseau pour une image que le serveur jettera.
      //
      //  90 Ko de PNG deviennent 120 Ko en base64 (+33 %), donc encore
      //  sous les 128 Ko du hub. Si quelqu'un remonte `poidsMaxMiroir`
      //  sans toucher au hub, ce test tombe — et c'est exactement son
      //  rôle.
      const int plafondHub = 128 * 1024;
      expect((poidsMaxMiroir * 4 / 3).round(), lessThan(plafondHub),
          reason: 'le base64 gonfle de 33 % : l\'app doit rester sous '
              'le plafond du hub MÊME une fois encodée');
    });

    test('la cadence laisse de la marge au plancher du hub', () {
      // Le hub refuse plus d'une image par 900 ms. L'app en envoie une
      // toutes les 2 s : elle ne doit jamais s'en approcher, sinon un
      // décalage d'horloge ferait sauter des images au hasard.
      expect(periodeMiroir.inMilliseconds, greaterThan(900 * 2));
    });
  });
}
