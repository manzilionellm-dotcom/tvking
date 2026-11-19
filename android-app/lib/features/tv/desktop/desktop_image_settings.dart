/// Choix du décodeur Windows, indépendant de la DLL pour pouvoir vérifier le
/// contrat. Le rendu GPU reste actif même si le décodage passe sur le CPU.
class DesktopImageSettings {
  String _engine = 'hardware';

  Map<String, Object> get capabilities => <String, Object>{
        'name': _engine,
        // Sur PC, « logiciel » utilise déjà FFmpeg/libmpv. Ne pas proposer
        // un troisième moteur identique sous un autre nom.
        'ffmpegVideo': false,
        'contrastHardware': false,
      };

  Future<void> apply(
    String requested, {
    required Future<void> Function(String, String) setProperty,
    required Future<String> Function(String) getProperty,
  }) async {
    // Une préférence FFmpeg héritée d'Android utilise le même décodeur CPU.
    final String engine = requested == 'software' || requested == 'ffmpeg'
        ? 'software'
        : 'hardware';
    final String value = engine == 'hardware' ? 'auto' : 'no';
    await setProperty('hwdec', value);
    // media_kit ne remonte pas tous les codes d'erreur de mpv_set_property.
    // Relire le réglage évite d'afficher un choix qui n'a pas été appliqué.
    // « auto » autorise le GPU, sans prétendre qu'un codec précis l'utilise.
    if (await getProperty('hwdec') != value) {
      throw StateError('Le réglage du décodeur libmpv n’a pas été appliqué.');
    }
    _engine = engine;
  }
}
