import 'ai_picture_status.dart';

export 'ai_picture_status.dart';

/// Informations provenant du lecteur courant, jamais du nom de la chaîne.
///
/// La taille est celle annoncée par la sortie vidéo, après les éventuels
/// effets. Ce n'est ni la résolution du téléviseur, ni une preuve de détail
/// natif du programme. Le format source garde ses propres dimensions.
/// Les métadonnées du flux et les compteurs de sortie restent séparés : un
/// fichier déclaré à 60 i/s ne prouve pas que 60 images/s sont rendues.
class NativeVideoQuality {
  const NativeVideoQuality({
    this.outputWidth = 0,
    this.outputHeight = 0,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.sourceMimeType,
    this.sourceDynamicRange,
    this.sourceFrameRate,
    this.cadence,
    this.aiPicture,
  });

  final int outputWidth;
  final int outputHeight;
  final int sourceWidth;
  final int sourceHeight;
  final String? sourceMimeType;
  final String? sourceDynamicRange;
  final double? sourceFrameRate;
  final NativeVideoCadence? cadence;
  final NativeAiPictureStatus? aiPicture;

  bool get hasOutputSize => outputWidth > 0 && outputHeight > 0;

  NativeVideoQuality withVideoSize(Object? raw) {
    final Map<Object?, Object?> data = _data(raw);
    return NativeVideoQuality(
      outputWidth: _dimension(data['width']),
      outputHeight: _dimension(data['height']),
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      sourceMimeType: sourceMimeType,
      sourceDynamicRange: sourceDynamicRange,
      sourceFrameRate: sourceFrameRate,
      cadence: cadence,
      aiPicture: aiPicture,
    );
  }

  NativeVideoQuality withSourceFormat(Object? raw) {
    final Map<Object?, Object?> data = _data(raw);
    final Object? mime = data['mimeType'];
    final Object? range = data['dynamicRange'];
    final Object? fps = data['frameRate'];
    return NativeVideoQuality(
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      sourceWidth: _dimension(data['width']),
      sourceHeight: _dimension(data['height']),
      sourceMimeType: mime is String && mime.startsWith('video/')
          ? mime
          : null,
      sourceDynamicRange: const <String>{'sdr', 'pq', 'hlg', 'dolbyVision'}
              .contains(range)
          ? range as String
          : null,
      sourceFrameRate:
          fps is num && fps.isFinite && fps > 0 && fps <= 1000
              ? fps.toDouble()
              : null,
    );
  }

  NativeVideoQuality withCadence(Object? raw) => NativeVideoQuality(
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        sourceMimeType: sourceMimeType,
        sourceDynamicRange: sourceDynamicRange,
        sourceFrameRate: sourceFrameRate,
        cadence: NativeVideoCadence.read(raw),
        aiPicture: aiPicture,
      );

  /// Le diagnostic IA ne remplace jamais les mesures source/sortie reçues
  /// de Media3. Les dimensions du shader restent dans son propre état.
  NativeVideoQuality withAiPicture(NativeAiPictureStatus? status) =>
      NativeVideoQuality(
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        sourceMimeType: sourceMimeType,
        sourceDynamicRange: sourceDynamicRange,
        sourceFrameRate: sourceFrameRate,
        cadence: cadence,
        aiPicture: status,
      );

  static Map<Object?, Object?> _data(Object? raw) =>
      raw is Map ? raw.cast<Object?, Object?>() : const <Object?, Object?>{};

  static int _dimension(Object? value) =>
      value is num && value.isFinite && value > 0 && value <= 32768
          ? value.toInt()
          : 0;
}

/// Deltas Media3 pendant une fenêtre de lecture continue et monotone.
/// Compte les buffers rendus/perdus par le décodeur, pas les rafraîchissements
/// de la dalle ni les éventuelles pertes après le traitement GL/HDMI.
class NativeVideoCadence {
  const NativeVideoCadence._(this.renderedFrames, this.droppedFrames, this.windowMs);

  final int renderedFrames;
  final int droppedFrames;
  final int windowMs;

  double get framesPerSecond => renderedFrames * 1000 / windowMs;

  static NativeVideoCadence? read(Object? raw) {
    if (raw is! Map) return null;
    final Object? rendered = raw['renderedFrames'];
    final Object? dropped = raw['droppedFrames'];
    final Object? window = raw['windowMs'];
    if (rendered is! int || dropped is! int || window is! int) return null;
    if (rendered < 0 || dropped < 0 || window < 2000 || window > 5000) {
      return null;
    }
    return NativeVideoCadence._(rendered, dropped, window);
  }
}
