import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Garde une largeur lisible sans grossir l'interface sur un moniteur 4K.
/// Les écrans existants demandent 1280 unités au minimum ; seule une
/// petite fenêtre nécessite une réduction. La hauteur reste disponible.
Size desktopDesignSize(Size available) {
  final double width = math.max(1280, available.width);
  return Size(width, width * available.height / available.width);
}
