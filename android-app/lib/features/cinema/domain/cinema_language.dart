// =========================================================
//  cinema_language.dart — Langue d'une catégorie + noms de langues
// =========================================================
//  L'API Xtream ne donne AUCUN champ « langue » pour un film ou une série
//  (vérifié sur la doc get_vod_streams / get_series). Les fournisseurs
//  l'écrivent dans le NOM de la catégorie : « FR | ACTION », « |EN| DRAMA »,
//  « [DE] Kino », « VOSTFR », « CHINESE MOVIES », « 华语电影 »…
//  On lit donc ce nom, avec deux niveaux de preuve :
//    1. les MOTS longs et sans ambiguïté (« french », « deutsch », « 中文 »)
//       comptent partout dans le nom ;
//    2. les CODES courts (« fr », « de », « en »…) ne comptent que s'ils sont
//       le 1er mot OU entourés de séparateurs (| [ ] ( ) : - /) — sinon le
//       « de » de « Films de Noël » passerait pour de l'allemand et le « en »
//       de « Films en VF » pour de l'anglais.
//  Si plusieurs langues sont citées, la PREMIÈRE dans le nom l'emporte
//  (« VOSTFR » = film étranger sous-titré français → rangé en français).
//
//  Sert aussi à afficher le nom d'une piste audio / sous-titres du lecteur
//  (« fre » → « Français », « chi » → « 中文 »).
// =========================================================

/// Détection de langue + libellés natifs.
abstract final class CinemaLanguage {
  /// Mots longs (≥ 4 lettres, ou écriture non latine) → langue.
  static const Map<String, List<String>> _words = <String, List<String>>{
    'fr': <String>['french', 'francais', 'france', 'vostfr', 'vf', 'vff', 'vfq', 'quebec', 'quebecois', 'francophone'],
    'en': <String>['english', 'anglais', 'american', 'british', 'hollywood'],
    'es': <String>['spanish', 'espanol', 'espana', 'latino', 'latin', 'castellano', 'mexico', 'mexicano'],
    'pt': <String>['portuguese', 'portugues', 'portugal', 'brazil', 'brasil', 'brasileiro', 'dublado'],
    'it': <String>['italian', 'italiano', 'italia', 'italy'],
    'de': <String>['german', 'deutsch', 'germany', 'deutschland', 'allemand'],
    'nl': <String>['dutch', 'nederlands', 'holland', 'vlaams', 'netherlands'],
    'ar': <String>['arabic', 'arab', 'arabe', 'arabia', 'maroc', 'morocco', 'marocain', 'algerie', 'algeria', 'tunisie', 'tunisia', 'egypt', 'egypte', 'liban', 'lebanon', 'syria', 'khaliji', 'shahid', 'عربي', 'عربية', 'العربية'],
    'tr': <String>['turkish', 'turkiye', 'turkey', 'turkce', 'turc'],
    'ru': <String>['russian', 'russia', 'russe', 'русск', 'россия'],
    'pl': <String>['polish', 'polska', 'polski'],
    'ro': <String>['romanian', 'romania', 'romana'],
    'el': <String>['greek', 'greece', 'ellada', 'ελλην'],
    'sv': <String>['swedish', 'svenska', 'sverige'],
    'da': <String>['danish', 'dansk', 'danmark'],
    'nb': <String>['norwegian', 'norsk', 'norge'],
    'fi': <String>['finnish', 'suomi'],
    'zh': <String>['chinese', 'china', 'mandarin', 'cantonese', 'hongkong', 'taiwan', '中文', '中国', '华语', '華語', '国语', '國語', '粤语', '粵語', '大陆', '港剧', '国产'],
    'ja': <String>['japanese', 'japan', 'anime', '日本'],
    'ko': <String>['korean', 'korea', 'kdrama', '한국'],
    'hi': <String>['hindi', 'bollywood', 'indian', 'india', 'हिंदी', 'हिन्दी'],
    'ta': <String>['tamil', 'kollywood', 'தமிழ்'],
    'te': <String>['telugu', 'tollywood', 'తెలుగు'],
    'ml': <String>['malayalam', 'mollywood'],
    'bn': <String>['bengali', 'bangla', 'বাংলা'],
    'ur': <String>['urdu', 'pakistan', 'اردو'],
    'fa': <String>['persian', 'farsi', 'iran', 'فارسی'],
    'he': <String>['hebrew', 'israel', 'עברית'],
    'ku': <String>['kurdish', 'kurdi'],
    'sq': <String>['albanian', 'albania', 'shqip'],
    'af': <String>['african', 'afrique', 'nollywood', 'nigeria'],
  };

  /// Codes courts (2-3 lettres) → langue. Comptent seulement en 1re position
  /// ou entre séparateurs (cf. en-tête).
  static const Map<String, List<String>> _codes = <String, List<String>>{
    'fr': <String>['fr', 'fra', 'fre'],
    'en': <String>['en', 'eng', 'uk', 'us', 'usa', 'gb'],
    'es': <String>['es', 'esp', 'spa', 'mx', 'lat'],
    'pt': <String>['pt', 'por', 'br'],
    'it': <String>['it', 'ita'],
    'de': <String>['de', 'ger', 'deu'],
    'nl': <String>['nl', 'dut', 'nld'],
    'ar': <String>['ar', 'ara', 'ksa'],
    'tr': <String>['tr', 'tur'],
    'ru': <String>['ru', 'rus'],
    'pl': <String>['pl', 'pol'],
    'ro': <String>['ro', 'rom'],
    'el': <String>['gr', 'gre'],
    'sv': <String>['se', 'swe'],
    'da': <String>['dk', 'dan'],
    'nb': <String>['no', 'nor'],
    'fi': <String>['fi', 'fin'],
    'zh': <String>['cn', 'chi', 'zh'],
    'ja': <String>['jp', 'jap', 'jpn'],
    'ko': <String>['kr', 'kor'],
    'hi': <String>['in', 'hin', 'ind'],
    'fa': <String>['ir', 'per'],
    'he': <String>['il', 'heb'],
    'sq': <String>['al', 'alb'],
  };

  /// Nom de chaque langue DANS SA PROPRE LANGUE (reconnaissable par celui
  /// qui la parle, quelle que soit la langue de l'app).
  static const Map<String, String> nativeNames = <String, String>{
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'it': 'Italiano',
    'de': 'Deutsch',
    'nl': 'Nederlands',
    'ar': 'العربية',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'pl': 'Polski',
    'ro': 'Română',
    'el': 'Ελληνικά',
    'sv': 'Svenska',
    'da': 'Dansk',
    'nb': 'Norsk',
    'fi': 'Suomi',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'ml': 'മലയാളം',
    'bn': 'বাংলা',
    'ur': 'اردو',
    'fa': 'فارسی',
    'he': 'עברית',
    'ku': 'Kurdî',
    'sq': 'Shqip',
    'af': 'Africa',
    'sw': 'Kiswahili',
  };

  /// Codes ISO 639-2 (pistes des fichiers mkv/mp4) → code court.
  static const Map<String, String> _iso3 = <String, String>{
    'fre': 'fr', 'fra': 'fr', 'eng': 'en', 'spa': 'es', 'por': 'pt',
    'ita': 'it', 'ger': 'de', 'deu': 'de', 'dut': 'nl', 'nld': 'nl',
    'ara': 'ar', 'tur': 'tr', 'rus': 'ru', 'pol': 'pl', 'rum': 'ro',
    'ron': 'ro', 'gre': 'el', 'ell': 'el', 'swe': 'sv', 'dan': 'da',
    'nor': 'nb', 'nob': 'nb', 'no': 'nb', 'fin': 'fi', 'chi': 'zh',
    'zho': 'zh', 'jpn': 'ja', 'kor': 'ko', 'hin': 'hi', 'tam': 'ta',
    'tel': 'te', 'mal': 'ml', 'ben': 'bn', 'urd': 'ur', 'per': 'fa',
    'fas': 'fa', 'heb': 'he', 'iw': 'he', 'kur': 'ku', 'alb': 'sq',
    'sqi': 'sq', 'swa': 'sw',
  };

  /// Codes qui sont AUSSI des mots courants (« in », « it », « de », « en »,
  /// « no », « us »…) : ils exigent un VRAI séparateur à côté (« |IN| »,
  /// « DE: », « [EN] »), jamais la simple 1re position (« In Theaters »).
  static const Set<String> _ambiguous = <String>{
    'in', 'it', 'no', 'us', 'se', 'al', 'il', 'de', 'en', 'es', 'per',
    'lat', 'rom', 'ind', 'ar', 'br', 'dan', 'fin', 'ir', 'pol', 'por',
  };

  static final RegExp _rxToken = RegExp(r'[a-z0-9]+');
  static final RegExp _rxSep = RegExp(r'[|\[\](){}:/•*#_\-–—]');

  /// Langue déduite d'un nom de catégorie, ou `null`.
  static String? detect(String categoryName) {
    final String raw = categoryName.trim();
    if (raw.isEmpty) return null;
    final String low = _fold(raw.toLowerCase());

    String? best;
    int bestPos = 1 << 30;
    void consider(String lang, int pos) {
      if (pos >= 0 && pos < bestPos) {
        bestPos = pos;
        best = lang;
      }
    }

    // 1) Mots longs / écritures non latines : n'importe où.
    _words.forEach((String lang, List<String> words) {
      for (final String w in words) {
        final int pos = _wordPos(low, w);
        if (pos >= 0) consider(lang, pos);
      }
    });

    // 2) Codes courts : 1er mot ou entre séparateurs.
    final List<RegExpMatch> tokens = _rxToken.allMatches(low).toList();
    for (int i = 0; i < tokens.length; i++) {
      final RegExpMatch t = tokens[i];
      final String tok = t.group(0)!;
      final bool realSep = _touchesSeparator(low, t.start, t.end);
      final bool ok = _ambiguous.contains(tok)
          ? (realSep || tokens.length == 1)
          : (realSep || i == 0 || i == tokens.length - 1);
      if (!ok) continue;
      _codes.forEach((String lang, List<String> codes) {
        if (codes.contains(tok)) consider(lang, t.start);
      });
    }
    return best;
  }

  /// Nom natif d'un code langue (court ou ISO 639-2), sinon le code en
  /// majuscules, sinon `null`.
  static String? labelFor(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final String c = normalizeCode(code);
    return nativeNames[c] ?? c.toUpperCase();
  }

  /// « fre » → « fr », « en-US » → « en », « zh-Hant » → « zh ».
  static String normalizeCode(String code) {
    String c = code.trim().toLowerCase();
    final int dash = c.indexOf(RegExp(r'[-_]'));
    if (dash > 0) c = c.substring(0, dash);
    return _iso3[c] ?? c;
  }

  // ---- internes ----

  /// Position d'un mot : pour l'alphabet latin on exige des bords de mot
  /// (« arab » ne doit pas matcher « parabole ») ; pour les autres écritures,
  /// une simple recherche suffit.
  static int _wordPos(String text, String word) {
    final bool latin = RegExp(r'^[a-z0-9]+$').hasMatch(word);
    if (!latin) return text.indexOf(word);
    int from = 0;
    while (true) {
      final int i = text.indexOf(word, from);
      if (i < 0) return -1;
      final bool startOk = i == 0 || !_isAlnum(text.codeUnitAt(i - 1));
      final int end = i + word.length;
      // « arab » accepte « arabic » / « arabe » (préfixe), mais pas l'inverse.
      final bool endOk = end >= text.length || !_isAlnum(text.codeUnitAt(end)) ||
          word.length >= 5;
      if (startOk && endOk) return i;
      from = i + 1;
    }
  }

  /// Un VRAI séparateur (| [ ] ( ) : - / …) touche-t-il le jeton
  /// [start, end[ (espaces ignorés) ? Les bords du texte ne comptent pas.
  static bool _touchesSeparator(String text, int start, int end) {
    for (int i = start - 1; i >= 0; i--) {
      final String ch = text[i];
      if (ch == ' ') continue;
      if (_rxSep.hasMatch(ch)) return true;
      break;
    }
    for (int i = end; i < text.length; i++) {
      final String ch = text[i];
      if (ch == ' ') continue;
      if (_rxSep.hasMatch(ch)) return true;
      break;
    }
    return false;
  }

  static bool _isAlnum(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);

  /// Retire les accents latins courants (é → e, ç → c, ü → u…).
  static String _fold(String s) {
    const String from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
    const String to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final StringBuffer b = StringBuffer();
    for (final int r in s.runes) {
      final String ch = String.fromCharCode(r);
      final int i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Normalisation de recherche : minuscules, sans accents, espaces uniques.
  static String searchKey(String s) =>
      _fold(s.toLowerCase()).replaceAll(RegExp(r'\s+'), ' ').trim();
}
