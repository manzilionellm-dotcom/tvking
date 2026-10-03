// =========================================================
//  audio_sources.dart — Compteur des sources de son
// =========================================================
//  Le son « vieille radio / dans un trou / guerre entre deux sons »
//  peut venir d'un DEUXIÈME lecteur qui a survécu à un zap ou à un
//  retour de Home. On ne l'entend pas depuis ici. On COMPTE.
//
//  Ce fichier ne joue rien, ne coupe rien, ne change aucun volume.
//  Chaque écran dit « j'existe » et « je sors du son » (ou plus).
//  La fiche Diagnostic relit le total.
//
//  [codeStopsOnHome] est la politique LUE dans les écrans (octobre 2026).
//  Le compteur ne s'en sert pas pour arrêter qui que ce soit : il sert
//  à comparer, sur l'appareil, « qui avait encore du son au Home ».
// =========================================================

/// Ce qu'une source fait en ce moment. Fermée = plus dans la carte.
enum AudioPresence {
  /// Le lecteur existe, le son est coupé (arrêt Home du plein écran).
  open,

  /// Du son sort, ou on vient de demander qu'il sorte.
  sound,

  /// Pause : la piste est gardée (réglage « Hors app : pause », ou pause).
  held,

  /// Micro du système (reconnaissance). Pas un film, mais le mode audio
  /// de l'appareil peut changer.
  mic,

  /// Service de premier plan (WakeLock). Ne décode pas de son tout seul.
  lock,
}

/// Une source nommée. [id] est stable (la fiche, les tests). [label]
/// est le mot affiché.
class AudioSourceKind {
  const AudioSourceKind(this.id, this.label);

  final String id;
  final String label;
}

/// Registre du processus. Un jeton = une instance (un lecteur, un
/// service, une écoute). Deux aperçus = deux jetons, le total le dit.
class AudioSources {
  AudioSources._();

  static const String pleinEcran = 'plein_ecran';
  static const String apercu = 'apercu';
  static const String film = 'film';
  static const String enregistrementTv = 'enregistrement_tv';
  static const String sonde = 'sonde';
  static const String temoin = 'temoin';
  static const String telephone = 'telephone';
  static const String pub = 'pub';
  static const String enregistrementTel = 'enregistrement_tel';
  static const String serviceFond = 'service_fond';
  static const String serviceEnregistrement = 'service_enregistrement';
  static const String voix = 'voix';
  static const String autre = 'autre';

  /// Ordre fixe dans la fiche, pour qu'une case à 0 se voie.
  static const List<AudioSourceKind> catalog = <AudioSourceKind>[
    AudioSourceKind(pleinEcran, 'plein écran'),
    AudioSourceKind(apercu, 'aperçu'),
    AudioSourceKind(film, 'film'),
    AudioSourceKind(enregistrementTv, 'enregistrement TV'),
    AudioSourceKind(sonde, 'sonde réseau'),
    AudioSourceKind(temoin, 'son témoin'),
    AudioSourceKind(telephone, 'téléphone'),
    AudioSourceKind(pub, 'pub'),
    AudioSourceKind(enregistrementTel, 'enregistrement téléphone'),
    AudioSourceKind(serviceFond, 'service de fond'),
    AudioSourceKind(serviceEnregistrement, 'service enregistrement'),
    AudioSourceKind(voix, 'voix'),
  ];

  /// Vrai = l'écran correspondant coupe le son au Home, dans le code
  /// d'aujourd'hui (réglages par défaut). Faux = personne ne le coupe.
  /// Le plein écran redevient faux si le réglage « Hors app : pause »
  /// est allumé : le compteur, lui, voit alors « piste gardée ».
  static const Map<String, bool> codeStopsOnHome = <String, bool>{
    pleinEcran: true,
    apercu: false,
    film: true,
    enregistrementTv: true,
    sonde: false,
    temoin: false,
    telephone: false,
    pub: false,
    enregistrementTel: false,
    serviceFond: false,
    serviceEnregistrement: false,
    voix: false,
  };

  static final Map<int, _Live> _live = <int, _Live>{};
  static int _seq = 0;

  /// Dernier Home : noms encore capables de son (ou micro).
  static List<String> lastHome = const <String>[];
  static bool homed = false;

  /// Dernier zap : qui sortait du son juste avant.
  static int zapCount = 0;
  static List<String> lastZap = const <String>[];

  /// Nombre de contrôleurs Dart inscrits (registre du plugin).
  /// L'app le branche au démarrage. 0 en test si on ne le branche pas.
  static int Function() controllerCount = () => 0;

  /// Prévenu quand la ligne change. N'est pas appelé par [debugReset].
  static void Function(String line)? onChange;

  static String _lastEmitted = '';

  /// Nouveau jeton, présence « ouvert » (pas encore de son).
  static int acquire(String id) {
    _seq += 1;
    _live[_seq] = _Live(id, AudioPresence.open);
    _emit();
    return _seq;
  }

  /// Déjà rendu : on ne décrémente pas en dessous de zéro.
  static void release(int token) {
    if (_live.remove(token) == null) return;
    _emit();
  }

  static void setPresence(int token, AudioPresence presence) {
    final _Live? row = _live[token];
    if (row == null || row.presence == presence) return;
    row.presence = presence;
    _emit();
  }

  /// Photo juste avant un changement de chaîne. Ne coupe rien.
  static void markZap() {
    zapCount += 1;
    lastZap = _namesWhere(_mixes);
    _emit();
  }

  /// Photo au Home (activité en pause). Ne coupe rien.
  static void markHome() {
    homed = true;
    lastHome = _namesWhere((AudioPresence p) => _mixes(p) || p == AudioPresence.mic);
    _emit();
  }

  /// Événements du [NativeVideoController] (plugin). Le plugin ne
  /// connaît pas cette classe : l'app branche le rappel au démarrage.
  static void onPlayerEvent(int token, String source, String event) {
    switch (event) {
      case 'open':
        _live[token] = _Live(source, AudioPresence.open);
        if (token > _seq) _seq = token;
        break;
      case 'close':
        _live.remove(token);
        break;
      case 'audible':
        final _Live? heard = _live[token];
        if (heard == null) return;
        heard.presence = AudioPresence.sound;
        break;
      case 'silent':
        final _Live? quiet = _live[token];
        if (quiet == null) return;
        quiet.presence = AudioPresence.open;
        break;
      case 'retain':
        final _Live? kept = _live[token];
        if (kept == null) return;
        kept.presence = AudioPresence.held;
        break;
      case 'zap':
        markZap();
        return;
      default:
        return;
    }
    _emit();
  }

  /// Ligne de la fiche. Aucune adresse, aucun secret : que des comptes.
  static String line() {
    final StringBuffer buf = StringBuffer('Sources :');
    for (final AudioSourceKind kind in catalog) {
      buf.write(' ');
      buf.write(_phrase(kind));
      buf.write(' ·');
    }
    final int autres = _count(autre);
    if (autres > 0) {
      buf.write(' autre $autres ·');
    }
    final List<String> mixing = _namesWhere(_mixes);
    buf.write(' Sons en même temps : ${mixing.length}');
    if (mixing.length > 1) {
      buf.write(' (${mixing.join(', ')}) ⚠ plusieurs sons');
    }
    buf.write('.');
    buf.write(' Contrôleurs Dart inscrits : ${controllerCount()}.');
    if (!homed) {
      buf.write(' Au dernier Home : pas encore quitté.');
    } else if (lastHome.isEmpty) {
      buf.write(' Au dernier Home : aucune source avec du son.');
    } else if (lastHome.length == 1) {
      buf.write(' Au dernier Home : ${lastHome.single} avait encore du son.');
    } else {
      buf.write(' Au dernier Home : ${lastHome.join(', ')} avaient encore du son.');
    }
    if (zapCount > 0) {
      buf.write(' Au dernier zap (n°$zapCount) : ${lastZap.length} avec du son');
      if (lastZap.isNotEmpty) buf.write(' (${lastZap.join(', ')})');
      buf.write('.');
    }
    return buf.toString();
  }

  /// Ajoute la ligne à une fiche (rapport de chaîne). Une ligne de
  /// journal (Zap, Focus…) n'est pas une fiche : on la laisse.
  static String attach(String diagnostic) {
    if (!_isSheet(diagnostic)) return diagnostic;
    final String row = line();
    final List<String> kept = <String>[];
    for (final String raw in diagnostic.split('\n')) {
      if (raw.trim().startsWith('Sources :')) continue;
      kept.add(raw);
    }
    while (kept.isNotEmpty && kept.last.trim().isEmpty) {
      kept.removeLast();
    }
    return '${kept.join('\n')}\n$row';
  }

  static bool _isSheet(String diagnostic) =>
      diagnostic.contains('Codec :') || diagnostic.contains('reçu :');

  /// Tests seulement. L'app ne remet pas les compteurs à zéro : ils
  /// durent autant que le processus, c'est le sujet.
  static void debugReset() {
    _live.clear();
    _seq = 0;
    lastHome = const <String>[];
    homed = false;
    zapCount = 0;
    lastZap = const <String>[];
    controllerCount = () => 0;
    onChange = null;
    _lastEmitted = '';
  }

  static bool _mixes(AudioPresence p) =>
      p == AudioPresence.sound || p == AudioPresence.held;

  static int _count(String id) {
    int n = 0;
    for (final _Live row in _live.values) {
      if (row.id == id) n += 1;
    }
    return n;
  }

  static String _phrase(AudioSourceKind kind) {
    final List<_Live> rows = <_Live>[
      for (final _Live row in _live.values)
        if (row.id == kind.id) row,
    ];
    if (rows.isEmpty) return '${kind.label} 0';
    final int sounds = rows.where((_Live r) => r.presence == AudioPresence.sound).length;
    final int held = rows.where((_Live r) => r.presence == AudioPresence.held).length;
    final int mics = rows.where((_Live r) => r.presence == AudioPresence.mic).length;
    final int locks = rows.where((_Live r) => r.presence == AudioPresence.lock).length;
    final String how;
    if (sounds > 0 && (held > 0 || rows.length > sounds)) {
      how = 'son $sounds/${rows.length}';
    } else if (sounds > 0) {
      how = 'son';
    } else if (held > 0) {
      how = 'piste gardée';
    } else if (mics > 0) {
      how = 'micro';
    } else if (locks > 0) {
      how = 'verrou, pas de son';
    } else {
      how = 'ouvert, son coupé';
    }
    return '${kind.label} ${rows.length} ($how)';
  }

  static List<String> _namesWhere(bool Function(AudioPresence) want) {
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final AudioSourceKind kind in catalog) {
      final bool hit = _live.values.any(
        (_Live row) => row.id == kind.id && want(row.presence),
      );
      if (hit && seen.add(kind.id)) names.add(kind.label);
    }
    return names;
  }

  static void _emit() {
    final String next = line();
    if (next == _lastEmitted) return;
    _lastEmitted = next;
    final void Function(String line)? hook = onChange;
    if (hook != null) hook(next);
  }
}

class _Live {
  _Live(this.id, this.presence);
  final String id;
  AudioPresence presence;
}
