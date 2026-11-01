import 'package:flutter/services.dart';

/// Compatibilité demandée pour la saisie manuelle de sources : le « s »
/// initial disparaît dès le collage de https://. Le reste du texte, y compris
/// le port, les identifiants et les URL dans les paramètres, reste identique.
/// Ce formateur n'est appliqué ni aux listes enregistrées ni aux appels panel.
class SourceHttpInputFormatter extends TextInputFormatter {
  const SourceHttpInputFormatter();

  static final RegExp _httpsPrefix = RegExp(
    r'^[\s\u200B-\u200D\u2060\uFEFF]*https://',
    caseSensitive: false,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Ne pas interrompre une composition du clavier (notamment asiatique).
    // La même normalisation sera faite quand le clavier valide le texte.
    if (!newValue.composing.isCollapsed) return newValue;
    final RegExpMatch? prefix = _httpsPrefix.firstMatch(newValue.text);
    if (prefix == null) return newValue;

    // « s:// » occupe les quatre derniers caractères du préfixe reconnu.
    // Retirer un seul caractère évite toute réécriture du lien signé/encodé.
    final int removedIndex = prefix.end - 4;
    int shift(int offset) => offset > removedIndex ? offset - 1 : offset;
    return newValue.copyWith(
      text: newValue.text.replaceRange(removedIndex, removedIndex + 1, ''),
      selection: newValue.selection.copyWith(
        baseOffset: shift(newValue.selection.baseOffset),
        extentOffset: shift(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
