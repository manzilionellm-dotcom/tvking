import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Dossier des données internes de ZUNO.
///
/// Android : inchangé (documents privés de l'app).
/// Windows : dossier de l'application (%APPDATA%\Zuno\Zuno), jamais
/// « Documents » : OneDrive, l'accès contrôlé aux dossiers ou une stratégie
/// d'entreprise peuvent l'interdire, et un paquet MSIX y virtualise
/// correctement AppData, pas Documents.
Future<Directory> zunoDataDirectory() async => Platform.isWindows
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();

/// Windows : la base des versions ≤ 113.0.3 vivait dans Documents. On la
/// COPIE une fois (base + journaux WAL/SHM) vers le nouveau dossier ; l'ancien
/// fichier reste en place comme sauvegarde. Ne lance jamais.
Future<void> migrateWindowsDocumentsFile(String fileName, Directory target,
    {Future<Directory> Function()? legacyDir}) async {
  if (!Platform.isWindows && legacyDir == null) return;
  try {
    final File dest = File(p.join(target.path, fileName));
    if (dest.existsSync()) return;
    final Directory docs =
        await (legacyDir ?? getApplicationDocumentsDirectory)();
    final File legacy = File(p.join(docs.path, fileName));
    if (!legacy.existsSync()) return;
    target.createSync(recursive: true);
    for (final String suffix in const <String>['-wal', '-shm']) {
      final File side = File('${legacy.path}$suffix');
      if (side.existsSync()) side.copySync('${dest.path}$suffix');
    }
    // Le fichier principal en DERNIER : sa présence marque la copie finie.
    legacy.copySync('${dest.path}.part');
    File('${dest.path}.part').renameSync(dest.path);
  } catch (_) {
    // Documents illisible : nouvelle base vide, l'app démarre quand même.
  }
}
