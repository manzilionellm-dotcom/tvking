// =========================================================
//  update_manifest.dart — Lecture stricte du version.json
// =========================================================
//  L'application ne propose une mise à jour que si le manifeste
//  donne l'empreinte SHA-256 et la taille exacte du fichier.
//  Sans ça, un fichier coupé ou remplacé pouvait être gardé.
//  Les box déjà installées avec l'ancien logiciel ignorent ces
//  champs : elles continuent de se mettre à jour. Cette version,
//  elle, refuse un manifeste incomplet (l'app déjà là reste).
// =========================================================

class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.mandatory,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final String sha256;
  final int sizeBytes;
  final bool mandatory;

  /// `null` si le manifeste est incomplet, plus vieux, ou sans
  /// empreinte. On ne devine pas.
  static UpdateManifest? tryParse(
    Object? decoded, {
    required int currentBuild,
  }) {
    if (decoded is! Map) return null;
    final Map<String, dynamic> j = Map<String, dynamic>.from(decoded);
    final int latest = (j['versionCode'] as num?)?.toInt() ?? 0;
    if (latest <= currentBuild) return null;
    final String url = (j['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final String sha = (j['sha256'] ?? '').toString().trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    final int size = (j['size'] as num?)?.toInt() ?? 0;
    if (size <= 0) return null;
    return UpdateManifest(
      versionCode: latest,
      versionName: (j['versionName'] ?? '').toString(),
      url: url,
      sha256: sha,
      sizeBytes: size,
      mandatory: j['mandatory'] == true,
    );
  }
}

/// Plusieurs manifestes (box de test : sa release de test ET celle des
/// clients). On garde le PLUS RÉCENT qui est complet et plus neuf que
/// l'app installée. Un manifeste cassé ou absent (`null`) est ignoré,
/// sans faire tomber les autres. À égalité, le premier de la liste gagne.
UpdateManifest? pickNewestManifest(
  List<Object?> decodedList, {
  required int currentBuild,
}) {
  UpdateManifest? best;
  for (final Object? decoded in decodedList) {
    final UpdateManifest? m =
        UpdateManifest.tryParse(decoded, currentBuild: currentBuild);
    if (m == null) continue;
    if (best == null || m.versionCode > best.versionCode) best = m;
  }
  return best;
}

/// Limites du téléchargement de l'APK (environ 55 Mo).
///
/// Avant : 3 minutes au total, soit au moins 2,5 Mbit/s. Une box en
/// Wi-Fi faible échouait à chaque essai, sans jamais se mettre à jour.
/// Maintenant : on abandonne si RIEN n'arrive pendant [idle] (réseau
/// coupé), ou au-delà de [total] (garde-fou), mais un débit lent et
/// régulier va jusqu'au bout (1 Mbit/s ≈ 8 minutes).
abstract final class UpdateDownloadLimits {
  static const Duration connect = Duration(seconds: 20);
  static const Duration idle = Duration(seconds: 45);
  static const Duration total = Duration(minutes: 20);

  /// Ancien comportement (repli `zuno.update.legacy`).
  static const Duration legacyTotal = Duration(minutes: 3);
}

/// Le fichier téléchargé est complet seulement si sa taille est
/// EXACTEMENT celle annoncée. Un Content-Length différent est un
/// refus. L'absence de Content-Length n'autorise pas un fichier
/// « assez gros ».
bool apkSizeMatches({
  required int received,
  required int expected,
  int? contentLength,
}) {
  if (expected <= 0 || received != expected) return false;
  if (contentLength != null && contentLength > 0 && contentLength != expected) {
    return false;
  }
  return true;
}
