// =========================================================
//  audio_passthrough.dart — Dolby / DTS vers l'ampli, sur le téléphone
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026), au vu du banc de la famille :
//  « implémente le passthrough Dolby comme sur la box, pour que le mpv
//  ne dépende plus du système. »
//
//  ---------------------------------------------------------
//  CE QUE FAIT LA BOX, ET CE QUE LE TÉLÉPHONE NE FAISAIT PAS
//  ---------------------------------------------------------
//  Sur la box, Media3 demande à Android si la sortie HDMI accepte
//  l'E-AC-3 / l'AC-3 / le DTS, et les lui envoie SANS les décoder :
//  l'ampli reçoit le vrai 5.1, pas un mixage stéréo. Le lecteur du
//  téléphone (mpv) ne pose pas cette question tout seul : sans
//  consigne, il décode tout en PCM et l'ampli branché en HDMI ou en
//  USB reçoit de la stéréo. C'était la seule différence AUDIBLE entre
//  les deux apps (banc du 19/09).
//
//  ---------------------------------------------------------
//  COMMENT ON LE FAIT
//  ---------------------------------------------------------
//  1. On pose la question à Android, par le plugin maison
//     (`getAudioPassthrough`) : quels formats compressés la sortie
//     ACTUELLE accepte tels quels. Réponse : une liste de noms mpv.
//  2. On la donne à mpv par `audio-spdif` — « ces formats-là, laisse-
//     les passer ». Tout ce qui n'est pas dans la liste est décodé
//     comme avant.
//  3. Si l'ampli refuse quand même (câble, réglage de la barre), mpv
//     retombe lui-même sur le décodage : JAMAIS de silence, c'est la
//     règle que la box applique déjà (repli AAC).
//
//  La liste est demandée à chaque ouverture de flux, pas mémorisée :
//  un client qui débranche son ampli au milieu de la soirée ne doit
//  pas garder une consigne qui ne correspond plus à sa sortie.
// =========================================================
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AudioPassthrough {
  /// Le canal du plugin maison (packages/tvking_device), le même que
  /// DeviceIdentity et DeviceMemory : une seule porte vers le natif.
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Les formats que mpv sait laisser passer, DANS L'ORDRE où on les
  /// écrit dans `audio-spdif`. Ordre fixe : l'ampli voit toujours la
  /// même consigne pour le même matériel, et un test le verrouille.
  static const List<String> formatsConnus = <String>[
    'ac3',
    'eac3',
    'dts',
    'dts-hd',
    'truehd',
  ];

  /// Formats acceptés tels quels par la sortie audio ACTUELLE.
  ///
  /// Vide hors Android, vide au moindre doute : « je ne sais pas »
  /// veut dire « décode toi-même », jamais « envoie et on verra ».
  static Future<List<String>> formats() async {
    if (!Platform.isAndroid) return const <String>[];
    try {
      // DEUX SECONDES, PAS UNE DE PLUS (20/09/2026). Le natif répond déjà
      // « rien » au bout de 1,5 s s'il attend le service audio ; ce délai
      // Dart est le filet au-dessus : quoi qu'il arrive côté Android, le
      // lecteur reçoit une réponse et démarre. Un flux qui attend une
      // sonde audio, c'est un client qui regarde une roue tourner.
      final List<Object?>? brut = await _channel
          .invokeMethod<List<Object?>>('getAudioPassthrough')
          .timeout(const Duration(seconds: 2));
      return brut?.whereType<String>().toList(growable: false) ??
          const <String>[];
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[AudioPassthrough] natif indisponible : $e');
      return const <String>[];
    }
  }

  /// La valeur de `audio-spdif` pour une liste de formats. Pure.
  ///
  /// Ne garde que les noms que mpv connaît, dans l'ordre de
  /// [formatsConnus], sans doublon. `''` = aucun passthrough (mpv
  /// décode tout) — c'est aussi ce qu'on lui écrit quand le client
  /// désactive l'option, pour EFFACER une consigne posée plus tôt.
  static String spdifPour(Iterable<String> formats) {
    final Set<String> voulus = formats.map((String f) => f.trim()).toSet();
    return formatsConnus.where(voulus.contains).join(',');
  }
}
