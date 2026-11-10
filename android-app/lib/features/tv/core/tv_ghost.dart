// Palette Noir Fantôme : noir OLED et reflets platine de la direction artistique.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

abstract final class TvGhost {
  /// La palette seule change ; la géométrie et le contenu restent ceux de Zuno.
  static const Color bg = AppColors.stealthBlack;
  static const Color panel = AppColors.stealthSurface;
  static const Color card = AppColors.stealthSurface;
  static const Color tile = AppColors.stealthSurface;
  static const Color sel = Color(0xFF1E1E25);
  static const Color surface3 = Color(0xFF24242C);
  static const Color line = Color(0xFF2B2B34);
  static const Color lineSoft = Color(0xFF202027);

  static const Color text = AppColors.stealthPlatinum;
  static const Color muted = AppColors.stealthMuted;
  static const Color mutedDim = Color(0xFF6C6B76);

  /// Accents platine identiques au téléphone.
  static const Color chrome = AppColors.stealthPlatinum;
  static const Color chromeBright = AppColors.stealthIce;
  static const Color chromeDeep = Color(0xFF7794B5);
  static const Color onChrome = AppColors.stealthBlack;

  /// Filet platine, un pixel. Lueur glace, jamais un néon.
  static const Color platinum = Color(0xFFE6EBF2);
  static const Color ice = Color(0xFFB7D4FF);

  /// Durée du balayage et de l'onde. Sous 300 ms.
  static const Duration shine = Duration(milliseconds: 240);
  static const Duration pulse = Duration(milliseconds: 200);

  /// Points du ciel. Assez peu pour rester un ciel, pas une neige.
  static const int starCount = 36;
}
