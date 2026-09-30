// =========================================================
//  box_text.dart — Textes courts des fonctions en plus
// =========================================================
//  Français d'abord (langue de la maison). Anglais si la box
//  est en anglais. Les autres langues retombent sur le français :
//  ces phrases sont locales à ces fonctions, pas au catalogue
//  des 16 fichiers .arb.
// =========================================================

import 'package:flutter/widgets.dart';

String boxText(BuildContext context, String fr, String en) {
  final String code = Localizations.localeOf(context).languageCode;
  return code == 'en' ? en : fr;
}
