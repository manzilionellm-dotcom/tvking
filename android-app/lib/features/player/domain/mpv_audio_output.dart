// =========================================================
//  mpv_audio_output.dart — Essai de sortie audio libmpv
// =========================================================
//  7 Motion (téléphone) joue avec media_kit / libmpv. media_kit pose
//  tout seul `ao=opensles` sur un appareil Android réel. La box Zuno,
//  elle, écrit dans un AudioTrack Media3. Ce fichier ne change PAS
//  cette sortie : il dit seulement quelle valeur d'essai est autorisée.
//
//  Coupé (chaîne vide, ou n'importe quoi d'autre que les trois noms) :
//  on ne touche pas à `ao`. Le son reste celui de media_kit.
//
//  On refuse `null` et toute chaîne libre : `ao=null` couperait le son,
//  et une faute de frappe ne doit pas envoyer une option inconnue.
// =========================================================

/// Choix d'essai pour la propriété mpv `ao`. Pur Dart, sans lecteur.
class MpvAudioOutput {
  MpvAudioOutput._();

  /// Clé SharedPreferences. Absente = essai coupé.
  static const String prefsKey = 'player.mpv_ao_trial';

  /// Les trois sorties qu'on a le droit d'essayer. `aaudio` peut être
  /// absent du libmpv embarqué : l'essai le dira, il ne l'invente pas.
  static const List<String> trials = <String>[
    'opensles',
    'audiotrack',
    'aaudio',
  ];

  /// Valeur que media_kit écrit lui-même sur un téléphone réel.
  /// On ne la réécrit que pour ANNULER un essai déjà appliqué.
  static const String mediaKitDefault = 'opensles';

  /// Valeur à passer à `setProperty('ao', …)`, ou null si l'essai est coupé.
  /// Null veut dire : ne pas appeler setProperty.
  static String? propertyValue(String? stored) {
    if (stored == null) return null;
    final String v = stored.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'off' || v == 'coupe' || v == 'coupé' || v == 'defaut' || v == 'défaut') {
      return null;
    }
    if (trials.contains(v)) return v;
    return null;
  }

  /// Les propriétés mpv qu'on relit ne doivent pas contenir d'adresse.
  /// Si une valeur en a une, on la remplace entière.
  static String redact(String raw) {
    final String trimmed = raw.trim();
    final String lower = trimmed.toLowerCase();
    if (lower.contains('http') ||
        lower.contains('://') ||
        lower.contains('password') ||
        lower.contains('token=')) {
      return '[masqué]';
    }
    if (trimmed.length <= 180) return trimmed;
    return '${trimmed.substring(0, 180)}…';
  }
}
