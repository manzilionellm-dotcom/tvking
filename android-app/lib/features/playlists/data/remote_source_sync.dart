// =========================================================
//  remote_source_sync.dart — Décision d'effacement panel → box
// =========================================================
//  Fichier SANS Flutter, pour qu'un `dart run` puisse prouver la
//  décision sans compiler l'application.
//
//  Le GET /api/device-source peut renvoyer `source: null` dans TROIS
//  cas très différents :
//    1. le panel a EFFACÉ la liste (tombstone : `cleared: true`) ;
//    2. aucune liste n'a jamais été assignée ;
//    3. la licence est bloquée (banned / frozen / expired) — le
//       worker renvoie alors source null SANS `cleared`.
//  Effacer l'écran sur tout `source: null` supprimerait les listes
//  que le client a ajoutées lui-même. On ne retire donc QUE les
//  listes déjà vues comme poussées par le panel, et SEULEMENT quand
//  le serveur dit `cleared: true` (ou quand il remplace le trio).
//
//  INTERRUPTEUR. Coupé par défaut (`false`). Un build normal ne
//  supprime rien et ne pose pas de minuteur à 2 s. Pour l'allumer
//  au moment d'un build voulu :
//    --dart-define=HONOR_REMOTE_LIST_CLEAR=true
//  Le worker qui envoie `cleared: true` doit AUSSI être déployé,
//  sinon même l'interrupteur allumé ne voit pas l'effacement.
// =========================================================

/// Effacement panel → box. `false` dans tout build qui ne passe pas
/// le `--dart-define` ci-dessus.
const bool kHonorRemoteListClear = bool.fromEnvironment(
  'HONOR_REMOTE_LIST_CLEAR',
  defaultValue: false,
);

/// Quand l'interrupteur est allumé, l'app redemande la source au plus
/// toutes les 2 s. Le délai réel = attente du prochain tick + réseau.
const Duration kRemoteClearPollInterval = Duration(seconds: 2);

/// Une playlist déjà en base, réduite à ce qu'il faut pour décider.
/// [key] est nul si on ne sait pas l'identifier : on ne la supprime pas.
class LocalSourceRef {
  const LocalSourceRef({required this.id, required this.key});

  final int id;
  final String? key;
}

/// Ce que [planRemoteListSync] demande à l'app d'exécuter.
class RemoteListSyncPlan {
  const RemoteListSyncPlan({
    required this.removeIds,
    required this.rememberKeys,
    required this.blockRestoreKeys,
  });

  /// Identifiants SQLite à passer à PlaylistRepository.deletePlaylist.
  /// Vide quand l'interrupteur est coupé.
  final List<int> removeIds;

  /// Identités panel à retenir pour un prochain effacement.
  final Set<String> rememberKeys;

  /// Identités qu'une restauration cloud ne doit pas ramener.
  /// Renseigné seulement quand l'interrupteur est allumé et que le
  /// serveur a vraiment effacé.
  final Set<String> blockRestoreKeys;
}

/// Clé stable d'une source JSON du worker.
/// Xtream : serveur + identifiant, JAMAIS le mot de passe.
/// M3U : l'URL. Autre type, ou champ vide : null (on n'y touche pas).
String? identityKeyFromSource(Map<String, dynamic> src) {
  final String type = (src['type'] as String?)?.trim().toLowerCase() ?? '';
  if (type == 'xtream') {
    final String server = (src['server_url'] as String?)?.trim() ?? '';
    final String user = (src['username'] as String?)?.trim() ?? '';
    if (server.isEmpty || user.isEmpty) return null;
    return 'xtream\n$server\n$user';
  }
  if (type == 'm3u') {
    final String m3u = (src['m3u_url'] as String?)?.trim() ?? '';
    if (m3u.isEmpty) return null;
    return 'm3u\n$m3u';
  }
  return null;
}

/// Même clé, calculée depuis une playlist locale ou un backup.
String? identityKeyForLocal({
  required String type,
  String? m3uUrl,
  String? xtreamServer,
  String? xtreamUsername,
}) {
  return identityKeyFromSource(<String, dynamic>{
    'type': type,
    'm3u_url': m3uUrl,
    'server_url': xtreamServer,
    'username': xtreamUsername,
  });
}

/// Sources réellement assignées dans la réponse publique.
/// Un tableau `sources` non vide gagne ; sinon l'objet `source`
/// historique. `source: null` et `sources: []` → liste vide.
List<Map<String, dynamic>> assignedSources(Map<String, dynamic> body) {
  final Object? list = body['sources'];
  if (list is List && list.isNotEmpty) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Object? item in list) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    if (out.isNotEmpty) return out;
  }
  final Object? source = body['source'];
  if (source is Map) {
    return <Map<String, dynamic>>[Map<String, dynamic>.from(source)];
  }
  return const <Map<String, dynamic>>[];
}

/// Identités présentes dans la réponse (sans mot de passe).
Set<String> payloadIdentityKeys(Map<String, dynamic> body) {
  final Set<String> keys = <String>{};
  for (final Map<String, dynamic> src in assignedSources(body)) {
    final String? key = identityKeyFromSource(src);
    if (key != null) keys.add(key);
  }
  return keys;
}

/// Décide quelles listes locales retirer.
///
/// [honorClear] false → [removeIds] toujours vide (clients actuels).
/// On UNION quand même les clés du payload dans [rememberKeys], pour
/// qu'un build ultérieur avec l'interrupteur allumé sache quoi retirer.
///
/// [honorClear] true :
///   - `cleared: true` et aucune source → retire les listes dont la clé
///     est dans [rememberedKeys]. Une liste jamais vue (ajoutée par le
///     client) reste.
///   - sources non vides → retire les clés mémorisées absentes du
///     nouveau payload (le panel a remplacé ou réduit le trio).
///   - `source: null` SANS `cleared` → ne retire rien (jamais assigné,
///     licence bloquée, ou ancien worker qui ne connaît pas le drapeau).
RemoteListSyncPlan planRemoteListSync({
  required bool honorClear,
  required List<LocalSourceRef> local,
  required Set<String> rememberedKeys,
  required Set<String> blockedRestoreKeys,
  required Map<String, dynamic> body,
}) {
  final Set<String> liveKeys = payloadIdentityKeys(body);
  final bool live = liveKeys.isNotEmpty;
  final bool explicitClear = !live && body['cleared'] == true;

  final Set<String> remember = Set<String>.of(rememberedKeys);
  final Set<String> blocked = Set<String>.of(blockedRestoreKeys);
  final List<int> removeIds = <int>[];

  if (honorClear && (explicitClear || live)) {
    for (final LocalSourceRef ref in local) {
      final String? key = ref.key;
      if (key == null || key.isEmpty) continue;
      if (!rememberedKeys.contains(key)) continue;
      if (explicitClear || !liveKeys.contains(key)) {
        removeIds.add(ref.id);
      }
    }
  }

  if (honorClear && explicitClear) {
    // Le panel n'a plus de liste. On oublie les clés (les ids à
    // supprimer sont déjà dans removeIds) et on interdit au backup
    // cloud de les réimporter au prochain démarrage.
    remember.clear();
    blocked.addAll(rememberedKeys);
  } else if (live) {
    remember.addAll(liveKeys);
    if (honorClear) {
      for (final LocalSourceRef ref in local) {
        final String? key = ref.key;
        if (key != null && removeIds.contains(ref.id)) {
          remember.remove(key);
        }
      }
      // Une ré-assignation lève le blocage de restauration.
      blocked.removeAll(liveKeys);
    }
  }

  return RemoteListSyncPlan(
    removeIds: List<int>.unmodifiable(removeIds),
    rememberKeys: Set<String>.unmodifiable(remember),
    blockRestoreKeys: Set<String>.unmodifiable(blocked),
  );
}
