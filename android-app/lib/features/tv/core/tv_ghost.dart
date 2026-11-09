// Palette Noir Fantôme : noir OLED et reflets platine de la direction artistique.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

abstract final class TvGhost {
  /// Fond absolu ; le halo de contenu reste un calque local de l’accueil.
  static const Color bg = AppColors.stealthBlack;
  static const Color panel = AppColors.stealthSurface;
  static const Color card = AppColors.stealthSurface;
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
