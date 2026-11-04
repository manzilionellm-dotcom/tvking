// =========================================================
//  tv_ghost.dart — Palette « Ghost » (Black Badge)
// =========================================================
//  Sources, pas une invention de néon :
//
//  • Rolls-Royce Black Badge Ghost (designboom, 28 oct. 2021) :
//    le noir le plus sombre de la marque, chrome assombri
//    (un micromètre, pas une peinture argent criarde), et un
//    ciel d'étoiles clairsemé — plus de 850 points dans la
//    planche de bord, pas un champ dense.
//    https://www.designboom.com/technology/2021-rolls-royce-black-badge-ghost-10-28-2021/
//  • Starlight Headliner (designboom, Cullinan Black Badge, 2019) :
//    1 344 fibres, huit étoiles filantes. L'effet est une
//    constellation rare, pas une pluie.
//    https://www.designboom.com/technology/rolls-royce-black-badge-cullinan-11-07-2019/
//
//  On ne copie pas le logo Rolls-Royce. On reprend le rapport :
//  noir très profond (pas #000 : le banding OLED est déjà noté
//  dans TvTokens), chrome sombre lisible, quelques points.
//
//  Le gris confort #121212 ne s'applique pas ici. Les surfaces
//  confort restent dans tv_comfort.dart.
//
//  Contrastes sur #050506 (calculés) : chrome #C5C9D1 ≈ 12:1,
//  texte #F4F6F8 ≈ 19:1, secondaire #B7BCC4 ≈ 11:1,
//  tertiaire #8B9098 ≈ 6,4:1. Le chrome profond #6E737C est
//  un filet (≈ 4,3:1), pas un texte.
// =========================================================
import 'package:flutter/material.dart';

abstract final class TvGhost {
  /// Obsidienne. Le #000 pur bande sur OLED ; la trame posée
  /// dessus casse l'aplat. Plus profond que #070708 et que #121212.
  static const Color bg = Color(0xFF010102);
  static const Color panel = Color(0xFF0C0C0E);
  static const Color card = Color(0xFF141416);
  static const Color tile = Color(0xFF18181B);
  static const Color sel = Color(0xFF222226);
  static const Color surface3 = Color(0xFF2A2A2E);
  static const Color line = Color(0xFF3A3A40);
  static const Color lineSoft = Color(0xFF2A2A2E);

  static const Color text = Color(0xFFF4F6F8);
  static const Color muted = Color(0xFFB7BCC4);
  static const Color mutedDim = Color(0xFF8B9098);

  /// Chrome sombre, pas l'or du soir.
  static const Color chrome = Color(0xFFC5C9D1);
  static const Color chromeBright = Color(0xFFF4F6F8);
  static const Color chromeDeep = Color(0xFF6E737C);
  static const Color onChrome = Color(0xFF121418);

  /// Filet platine, un pixel. Lueur glace, jamais un néon.
  static const Color platinum = Color(0xFFE6EBF2);
  static const Color ice = Color(0xFFB7D4FF);

  /// Durée du balayage et de l'onde. Sous 300 ms.
  static const Duration shine = Duration(milliseconds: 240);
  static const Duration pulse = Duration(milliseconds: 200);

  /// Points du ciel. Assez peu pour rester un ciel, pas une neige.
  static const int starCount = 36;
}
