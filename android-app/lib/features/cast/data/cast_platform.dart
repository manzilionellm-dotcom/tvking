import 'package:flutter/foundation.dart';

import '../../../core/app/zuno_edition.dart';
import '../domain/cast_device.dart';

/// Le moteur réseau de 7 MOTION fonctionne sur PC. Le pont Google Cast
/// reste un SDK Android : on ne présente jamais un appareil non pilotable.
abstract final class CastPlatform {
  static ZunoEdition? _zunoEdition;

  /// Appelé avant les services et widgets ZUNO. `null` au départ conserve
  /// le comportement des entrées 7 MOTION qui ne configurent pas ZUNO.
  static void configureZuno(ZunoEdition edition) => _zunoEdition = edition;

  static ZunoEdition? get zunoEdition => _zunoEdition;

  /// La décision vient de l'édition compilée, jamais d'une largeur d'écran,
  /// du D-pad ou de `AppPlatform.isTv` (qui sert aussi au panel Windows).
  /// Les écrans doivent consulter cette garde AVANT de créer un widget Cast
  /// ou de toucher au singleton qui lance ses services de découverte.
  static bool get canSend => _zunoEdition != ZunoEdition.television;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool supports(CastDeviceKind kind) =>
      canSend &&
      (!isWindows ||
          kind == CastDeviceKind.dlna ||
          kind == CastDeviceKind.roku);

  @visibleForTesting
  static void resetForTesting() => _zunoEdition = null;
}
