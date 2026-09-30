// =========================================================
//  image_engine.dart — moteur d'image choisi par la personne
// =========================================================
//  Trois noms, les mêmes que le natif (VideoEngine.wire) :
//    hardware = décodeur de la box (réglage d'origine, v102–v104) ;
//    software = décodeur logiciel Android, devant le matériel ;
//    ffmpeg   = rendu vidéo FFmpeg, seulement s'il sait lire la vidéo.
//
//  Le bouton du lecteur avance d'un cran. Si FFmpeg vidéo n'est pas
//  dans l'APK, on ne s'arrête pas dessus : on le signale et on
//  revient au matériel. Rien ici n'ouvre un flux.
// =========================================================

enum ImageEngine {
  hardware('hardware'),
  software('software'),
  ffmpeg('ffmpeg');

  const ImageEngine(this.wire);

  /// Valeur envoyée au lecteur natif.
  final String wire;

  static ImageEngine fromWire(String? raw) {
    for (final ImageEngine engine in values) {
      if (engine.wire == raw) return engine;
    }
    return ImageEngine.hardware;
  }
}

/// Un cran du bouton « moteur ». [ffmpegMissing] = on a sauté FFmpeg
/// parce que la bibliothèque native ne décode pas la vidéo.
class EngineStep {
  const EngineStep(this.engine, {this.ffmpegMissing = false});

  final ImageEngine engine;
  final bool ffmpegMissing;

  /// [ffmpegVideo] vient du natif (`FfmpegLibrary.supportsFormat`).
  /// Faux tant qu'on ne l'a pas reçu : on ne propose pas un moteur
  /// dont on ne sait pas s'il existe.
  static EngineStep next(ImageEngine current, {required bool ffmpegVideo}) {
    switch (current) {
      case ImageEngine.hardware:
        return const EngineStep(ImageEngine.software);
      case ImageEngine.software:
        if (ffmpegVideo) return const EngineStep(ImageEngine.ffmpeg);
        return const EngineStep(ImageEngine.hardware, ffmpegMissing: true);
      case ImageEngine.ffmpeg:
        return const EngineStep(ImageEngine.hardware);
    }
  }
}

/// Le filtre de contraste ne s'applique que si le natif a dit que
/// le matériel le permet. Cette version dit non : le filtre OpenGL
/// quitterait la Surface qui affiche l'image.
class PictureTuneChoice {
  const PictureTuneChoice._();

  static bool resolve({required bool requested, required bool hardwareAllows}) =>
      requested && hardwareAllows;
}
