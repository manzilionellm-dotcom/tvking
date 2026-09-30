// =========================================================
//  image_engine.dart — moteur d'image choisi par la personne
// =========================================================
//  Trois noms, les mêmes que le lecteur TV :
//    hardware = décodeur de la puce (réglage d'origine) ;
//    software = décodage logiciel ;
//    ffmpeg   = rendu vidéo FFmpeg séparé, seulement s'il existe.
//
//  Sur le téléphone, libmpv EST le décodeur logiciel. Il n'y a pas
//  un troisième moteur vidéo dans ce binaire : le bouton saute
//  FFmpeg et le dit. Rien ici n'ouvre un flux.
// =========================================================

enum ImageEngine {
  hardware('hardware'),
  software('software'),
  ffmpeg('ffmpeg');

  const ImageEngine(this.wire);

  /// Valeur mémorisée et envoyée au lecteur.
  final String wire;

  static ImageEngine fromWire(String? raw) {
    for (final ImageEngine engine in values) {
      if (engine.wire == raw) return engine;
    }
    return ImageEngine.hardware;
  }
}

/// Un cran du bouton « moteur ». [ffmpegMissing] = on a sauté FFmpeg
/// parce que ce binaire n'a pas de décodeur vidéo FFmpeg à part.
class EngineStep {
  const EngineStep(this.engine, {this.ffmpegMissing = false});

  final ImageEngine engine;
  final bool ffmpegMissing;

  /// [ffmpegVideo] vient du binaire. Faux sur le téléphone : le
  /// logiciel, c'est déjà libmpv. On ne propose pas un moteur absent.
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

/// Propriété libmpv `hwdec` pour ce moteur.
/// Matériel : `auto-safe` (la puce, repli si elle refuse de démarrer).
/// Logiciel et FFmpeg : `no` (libmpv décode lui-même).
String hwdecFor(ImageEngine engine) =>
    engine == ImageEngine.hardware ? 'auto-safe' : 'no';
