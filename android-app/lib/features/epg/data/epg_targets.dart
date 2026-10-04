// =========================================================
//  epg_targets.dart — À quelles chaînes de l'app va un programme XMLTV
// =========================================================
//  Un fichier XMLTV désigne ses chaînes par un identifiant (« TF1.fr »).
//    • M3U : c'est le tvg-id, qui est aussi l'identifiant de la chaîne
//      dans l'app → le programme va à la chaîne du même nom.
//    • Xtream : l'app nomme ses chaînes `xtream-<stream_id>` et le serveur
//      donne, pour chacune, un `epg_channel_id` qui est l'identifiant du
//      XMLTV. Plusieurs chaînes (« TF1 HD », « TF1 FHD ») portent souvent le
//      même `epg_channel_id` : le programme va à CHACUNE.
//  Jusqu'au 4 octobre 2026, le guide des sources Xtream n'était jamais
//  importé (identifiants jamais appariés) : « En retard », « Tes
//  émissions », rappels et rattrapage restaient vides pour ces clients.
//  Fonction pure, testée sans base ni réseau.
// =========================================================

/// Identifiants de chaînes de l'app qui reçoivent le programme XMLTV
/// [xmltvId]. Sans [idMap] (M3U), l'identifiant est le même. Avec
/// (Xtream), seuls les appariements connus comptent : vide = à ignorer.
List<String> expandEpgTargets(String xmltvId, Map<String, List<String>>? idMap) {
  if (idMap == null) return <String>[xmltvId];
  return idMap[xmltvId] ?? const <String>[];
}

/// Construit l'appariement XMLTV → chaînes de l'app à partir de la table
/// `chaîne de l'app → epg_channel_id` renvoyée par le serveur Xtream.
/// Les identifiants vides sont ignorés ; la casse et les espaces sont
/// normalisés (certains serveurs écrivent « tf1.fr » d'un côté et
/// « TF1.fr » de l'autre).
Map<String, List<String>> buildEpgIdMap(Map<String, String> channelToEpgId) {
  final Map<String, List<String>> out = <String, List<String>>{};
  channelToEpgId.forEach((String channelId, String epgId) {
    final String key = normalizeEpgId(epgId);
    if (key.isEmpty) return;
    out.putIfAbsent(key, () => <String>[]).add(channelId);
  });
  return out;
}

/// Clé de comparaison d'un identifiant XMLTV.
String normalizeEpgId(String raw) => raw.trim().toLowerCase();
