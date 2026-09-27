// =========================================================
//  carousel_sound.dart — Sons du carrousel (≈ « useSound »)
// =========================================================
//  Équivalent Flutter du hook React `useSound` + Web Audio API :
//    • tick()   : clic bref et discret à chaque changement de carte ;
//    • select() : petit accord ascendant à la confirmation (OK / Entrée).
//  Contrainte du cahier des charges : AUCUN fichier audio → les sons sont
//  SYNTHÉTISÉS (oscillateur + enveloppe), comme `OscillatorNode` +
//  `GainNode` en Web Audio.
//
//  Implémentation à l'étape 5. Ce squelette fixe le contrat pour que le
//  widget puisse déjà l'appeler (silencieux tant que l'étape 5 n'est pas
//  faite).
// =========================================================
import '../domain/carousel_config.dart';

class CarouselSound {
  CarouselSound(this.config);

  final CarouselConfig config;

  /// Changement de carte.
  void tick() {}

  /// Confirmation de la carte sélectionnée.
  void select() {}

  /// Libère les ressources audio.
  void dispose() {}
}
