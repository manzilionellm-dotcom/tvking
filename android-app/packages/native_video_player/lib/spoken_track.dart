// =========================================================
//  spoken_track.dart — quelle piste audio on met par défaut
// =========================================================
//  Beaucoup de flux IPTV ont 2 pistes : la voix du programme, et un
//  commentaire / une audiodescription. ExoPlayer prend souvent la
//  première. Ici on choisit :
//    1. la langue de l'application, si une piste la porte ;
//    2. jamais un commentaire ni une audiodescription, s'il existe
//       une autre piste ;
//    3. on ne change rien si la piste déjà choisie convient
//       (éviter un second basculement qui craque).
//
//  La même règle est écrite en Kotlin
//  (SpokenTrackChoice.kt) pour le lecteur Android, qui décide AVANT
//  que le son sorte. Les deux doivent rester d'accord : les tests
//  des deux côtés couvrent les mêmes cas.
// =========================================================

/// Une piste audio déjà annoncée par le lecteur.
class SpokenTrack {
  const SpokenTrack({
    required this.group,
    required this.index,
    this.language,
    this.label,
    this.channels = 0,
    this.selected = false,
    this.roleFlags = 0,
  });

  final int group;
  final int index;
  final String? language;
  final String? label;
  final int channels;
  final bool selected;

  /// Drapeaux de rôle Media3 (C.ROLE_FLAG_*). 0 = le flux n'a rien dit.
  final int roleFlags;
}

/// Drapeaux Media3 (androidx.media3.common.C), recopiés ici pour
/// décider sans importer le SDK Android. 1 << 3 et 1 << 9.
const int kRoleCommentary = 8;
const int kRoleDescribesVideo = 512;

const Set<String> _kUndetermined = <String>{
  'und',
  'undetermined',
  'mul',
  'mis',
  'zxx',
  'xx',
};

/// Codes ISO 639-2 les plus fréquents sur les pistes IPTV → code court.
const Map<String, String> _kIso3 = <String, String>{
  'fre': 'fr',
  'fra': 'fr',
  'eng': 'en',
  'spa': 'es',
  'por': 'pt',
  'ita': 'it',
  'ger': 'de',
  'deu': 'de',
  'dut': 'nl',
  'nld': 'nl',
  'ara': 'ar',
  'tur': 'tr',
  'rus': 'ru',
  'pol': 'pl',
  'swe': 'sv',
  'dan': 'da',
  'nor': 'nb',
  'nob': 'nb',
  'nno': 'nb',
  'fin': 'fi',
  'chi': 'zh',
  'zho': 'zh',
  'jpn': 'ja',
  'kor': 'ko',
  'ron': 'ro',
  'rum': 'ro',
  'gre': 'el',
  'ell': 'el',
  'cze': 'cs',
  'ces': 'cs',
  'hun': 'hu',
  'ukr': 'uk',
  'vie': 'vi',
  'tha': 'th',
  'hin': 'hi',
  'ind': 'id',
};

/// « fre » → « fr », « en-US » → « en ». null si vide ou « und ».
String? spokenLanguage(String? raw) {
  if (raw == null) return null;
  String code = raw.trim().toLowerCase();
  if (code.isEmpty) return null;
  final int dash = code.indexOf(RegExp(r'[-_]'));
  if (dash > 0) code = code.substring(0, dash);
  code = _kIso3[code] ?? code;
  if (_kUndetermined.contains(code)) return null;
  return code;
}

/// Mots qui désignent un commentaire ou une audiodescription,
/// pas la voix du programme. Comparés à des mots entiers.
const Set<String> _kSideWords = <String>{
  'commentary',
  'commentaire',
  'commentaires',
  'comment',
  'comments',
  'descriptive',
  'description',
  'audiodescription',
  'audiodesc',
  'director',
  'narration',
  'narrateur',
  'narrator',
  'voiceover',
  'voixoff',
  'ad',
};

final RegExp _kWord = RegExp(r'[a-z0-9]+');

String _fold(String raw) {
  const String from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const String to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final StringBuffer out = StringBuffer();
  for (final int rune in raw.toLowerCase().runes) {
    final String ch = String.fromCharCode(rune);
    final int i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// Vrai si le libellé ou le rôle dit « ce n'est pas la voix principale ».
bool isSideTrack(SpokenTrack track) {
  if ((track.roleFlags & kRoleCommentary) != 0) return true;
  if ((track.roleFlags & kRoleDescribesVideo) != 0) return true;
  final String blob = _fold('${track.label ?? ''} ${track.language ?? ''}');
  for (final RegExpMatch match in _kWord.allMatches(blob)) {
    final String word = match.group(0) ?? '';
    if (_kSideWords.contains(word)) return true;
  }
  return false;
}

/// Piste à forcer, ou null si on garde le choix actuel.
///
/// [appLanguage] : langue de l'application (« fr », « fre », « en-US »).
SpokenTrack? chooseSpokenTrack(List<SpokenTrack> tracks, String? appLanguage) {
  if (tracks.isEmpty) return null;
  final String? want = spokenLanguage(appLanguage);
  final List<SpokenTrack> main = <SpokenTrack>[
    for (final SpokenTrack track in tracks)
      if (!isSideTrack(track)) track,
  ];
  SpokenTrack? selected;
  for (final SpokenTrack track in tracks) {
    if (track.selected) {
      selected = track;
      break;
    }
  }

  List<SpokenTrack> pool = main;
  if (want != null) {
    final List<SpokenTrack> inLang = <SpokenTrack>[
      for (final SpokenTrack track in main)
        if (spokenLanguage(track.language) == want) track,
    ];
    if (inLang.isNotEmpty) pool = inLang;
  }

  if (pool.isEmpty) {
    // Que des commentaires : on ne coupe pas le son, on ne change rien.
    return null;
  }

  if (selected != null) {
    for (final SpokenTrack track in pool) {
      if (track.group == selected.group && track.index == selected.index) {
        return null;
      }
    }
  }
  return pool.first;
}
