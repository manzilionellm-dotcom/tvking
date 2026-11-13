import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Une version Play ouvre la fiche de SON paquet : elle ne doit jamais
/// interpréter l'absence de manifeste APK comme la preuve qu'elle est à jour.
/// Google décide des versions accessibles à l'appareil et de l'installation.
Future<bool> openPlayStoreUpdate() async {
  try {
    final PackageInfo package = await PackageInfo.fromPlatform();
    if (package.packageName.isEmpty) return false;
    final Uri listing = Uri.https('play.google.com', '/store/apps/details',
        <String, String>{'id': package.packageName});
    return await launchUrl(listing, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Une TV sans application capable d'ouvrir le Store reste utilisable.
    // L'écran propose de réessayer sans annoncer une mise à jour réussie.
    return false;
  }
}
