// =========================================================
//  main_windows.dart — Zuno sur PC (Windows)
// =========================================================
//  MÊME application que la box : même démarrage (bootstrapZunoTv), mêmes
//  écrans, même design, même panel (activation par MAC, licence, sources
//  poussées). Seules trois briques changent, parce qu'elles sont
//  Android-uniquement sur la box :
//
//    1. BASE DE DONNÉES : Windows n'a pas de SQLite système → moteur FFI
//       (sqflite_common_ffi) branché comme fabrique globale AVANT toute
//       ouverture de base.
//    2. LECTEUR : ExoPlayer n'existe pas sur PC → media_kit (libmpv,
//       décodage matériel) derrière le MÊME NativeVideoController.
//    3. FENÊTRE / CLAVIER : plein écran, Échap = Retour, F11 = plein écran.
//
//  Build : flutter build windows --release --target=lib/main_windows.dart
//  (workflow .github/workflows/build-zuno-windows.yml).
// =========================================================
import 'package:media_kit/media_kit.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app/guarded_main.dart';
import 'features/tv/desktop/desktop_shell.dart';
import 'features/tv/desktop/media_kit_video_backend.dart';
import 'main_tv.dart';

void main() => runGuarded(_bootstrapWindows);

Future<void> _bootstrapWindows() async {
  // 1) SQLite embarqué (avant toute ouverture de base).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 2) Lecteur PC (libmpv) derrière le contrat du lecteur de la box.
  MediaKit.ensureInitialized();
  NativeVideoController.backendFactory = MediaKitVideoBackend.new;

  // 3) Fenêtre plein écran « Zuno ».
  await DesktopWindow.prepare();

  // Puis EXACTEMENT le démarrage de la box, avec les raccourcis PC autour.
  await bootstrapZunoTv(wrap: (app) => DesktopShell(child: app));
}
