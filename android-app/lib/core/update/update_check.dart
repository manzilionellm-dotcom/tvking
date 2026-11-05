import 'update_manifest.dart';

enum UpdateCheckStatus { available, upToDate, unavailable, unsupported }

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.manifest});

  final UpdateCheckStatus status;
  final UpdateManifest? manifest;
}

/// Les canaux sont lus ensemble : un canal lent ne double pas l'attente.
/// « À jour » exige que TOUS les canaux attendus aient répondu correctement.
/// Une nouvelle version complète reste utilisable si l'autre canal est absent.
Future<UpdateCheckResult> checkUpdateManifests({
  required Iterable<String> urls,
  required int currentBuild,
  required Future<Object?> Function(String url) read,
}) async {
  final List<String> unique = urls.toSet().toList(growable: false);
  final List<UpdateManifest?> manifests = await Future.wait(
    unique.map((String url) async {
      try {
        return UpdateManifest.tryParse(await read(url), currentBuild: 0);
      } catch (_) {
        return null;
      }
    }),
  );
  UpdateManifest? newest;
  for (final UpdateManifest? manifest in manifests) {
    if (manifest != null &&
        manifest.versionCode > currentBuild &&
        (newest == null || manifest.versionCode > newest.versionCode)) {
      newest = manifest;
    }
  }
  if (newest != null) {
    return UpdateCheckResult(UpdateCheckStatus.available, manifest: newest);
  }
  return UpdateCheckResult(
    manifests.isNotEmpty && manifests.every((m) => m != null)
        ? UpdateCheckStatus.upToDate
        : UpdateCheckStatus.unavailable,
  );
}
