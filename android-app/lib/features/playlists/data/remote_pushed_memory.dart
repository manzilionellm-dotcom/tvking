// =========================================================
//  remote_pushed_memory.dart — Mémoire des listes poussées
// =========================================================
//  On retient, sur l'appareil, l'identité des listes que le panel a
//  déjà envoyées (URL M3U, ou serveur Xtream + identifiant).
//  Pas de mot de passe, pas de contenu de flux.
//
//  Pourquoi : le jour où l'interrupteur HONOR_REMOTE_LIST_CLEAR est
//  allumé, l'app doit savoir QUELLE liste locale venait du panel.
//  Une liste ajoutée par le client n'est jamais dans ce carnet, donc
//  un effacement panel ne la supprime pas.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class RemotePushedMemory {
  const RemotePushedMemory({
    required this.remembered,
    required this.blocked,
  });

  /// Clés vues dans une réponse du panel (voir identityKeyFromSource).
  final Set<String> remembered;

  /// Clés effacées par le panel : la restauration cloud les saute.
  final Set<String> blocked;

  static const String _kRemembered = 'remote_pushed_source_keys.v1';
  static const String _kBlocked = 'remote_cleared_block_keys.v1';

  static Future<RemotePushedMemory> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return RemotePushedMemory(
      remembered:
          (prefs.getStringList(_kRemembered) ?? const <String>[]).toSet(),
      blocked: (prefs.getStringList(_kBlocked) ?? const <String>[]).toSet(),
    );
  }

  static Future<void> save({
    required Set<String> remembered,
    required Set<String> blocked,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> rememberedList = remembered.toList()..sort();
    final List<String> blockedList = blocked.toList()..sort();
    await prefs.setStringList(_kRemembered, rememberedList);
    await prefs.setStringList(_kBlocked, blockedList);
  }
}
