import 'package:flutter/services.dart';

/// Le schéma tapé ou collé reste exactement celui saisi.
///
/// `http://` ne gagne jamais de « s », et `https://` n'en perd jamais.
/// Le clavier (suggestions, correction automatique) est coupé sur les
/// champs d'adresse. `http://` n'est ajouté qu'à la validation, et
/// seulement quand aucun schéma n'a été donné.
class SourceHttpInputFormatter extends TextInputFormatter {
  const SourceHttpInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue;
  }
}
