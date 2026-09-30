// =========================================================
//  remote_actions.dart — Appliquer une commande déjà vérifiée
// =========================================================
//  Le serveur n'appelle ceci QU'APRÈS l'appairage, l'expiration
//  et la liste fermée. Ici on ne revalide pas le réseau : on
//  distribue.
//
//  Texte :
//    1. si un champ est en train d'être édité (ajouter une source…),
//       on REMPLACE son contenu par ce que le téléphone a tapé ;
//    2. sinon, l'écran de recherche qui s'est inscrit (Direct ou
//       Cinéma) reçoit le texte ;
//    3. sinon, on ne fait rien. On n'invente pas des touches lettre
//       par lettre dans un menu.
// =========================================================

import 'package:flutter/widgets.dart';

import '../domain/remote_command.dart';
import '../domain/remote_typing_hub.dart';
import 'remote_platform.dart';

Future<void> applyRemoteCommand(RemoteCommand command) async {
  if (command is RemoteQuery) {
    if (tryApplyRemoteTextToFocusedField(command.text)) return;
    RemoteTypingHub.instance.apply(command.text);
    return;
  }
  if (command is RemotePress) {
    await RemotePlatform.press(command.button);
  }
}

/// Vrai si un [TextField] (ou tout [EditableText]) a le focus et a
/// reçu le texte. Faux s'il n'y a pas de champ : l'appelant essaie
/// alors la recherche.
bool tryApplyRemoteTextToFocusedField(String text) {
  try {
    final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return false;
    final EditableTextState? field =
        ctx.findAncestorStateOfType<EditableTextState>();
    if (field == null || !field.mounted) return false;
    field.widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return true;
  } catch (_) {
    debugPrint('[remote] champ texte non mis à jour');
    return false;
  }
}
