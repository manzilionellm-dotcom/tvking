// =========================================================
//  audio_report_book.dart — Rapport de son, une fiche par chaîne
// =========================================================
//  Texte court, déjà produit par le lecteur (Kotlin). Ici on ne fait
//  que le RANGER : plafond de taille, une fiche par chaîne, et on
//  retire une URL ou un mot de passe si jamais il s'en était glissé un.
//  Rien n'est envoyé. Objet pur : testé sans disque.
// =========================================================

class AudioReportEntry {
  const AudioReportEntry({
    required this.channel,
    required this.body,
    required this.atMs,
  });

  final String channel;
  final String body;
  final int atMs;

  Map<String, Object> toJson() => <String, Object>{
        'channel': channel,
        'body': body,
        'atMs': atMs,
      };

  static AudioReportEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String channel = (raw['channel'] as String?)?.trim() ?? '';
    final String body = (raw['body'] as String?) ?? '';
    final int atMs = (raw['atMs'] as num?)?.toInt() ?? 0;
    if (channel.isEmpty || body.isEmpty) return null;
    return AudioReportEntry(channel: channel, body: body, atMs: atMs);
  }
}

class AudioReportBook {
  const AudioReportBook(this.entries);

  /// Plus récent en tête. Une seule fiche par nom de chaîne.
  final List<AudioReportEntry> entries;

  static const int maxEntries = 20;
  static const int maxBytes = 48 * 1024;
  static const int maxBodyChars = 4000;

  static const AudioReportBook empty = AudioReportBook(<AudioReportEntry>[]);

  AudioReportBook add({
    required String channel,
    required String body,
    required int atMs,
  }) {
    final String key = channelKey(channel);
    final String clean = clip(redactAudioText(body).trim());
    if (clean.isEmpty) return this;
    AudioReportEntry? prev;
    for (final AudioReportEntry e in entries) {
      if (e.channel == key) {
        prev = e;
        break;
      }
    }
    // Une ligne de journal (Seconde, Zap, Focus…) s'ajoute à la fiche.
    // Elle ne la remplace pas : sinon la fiche devenait la dernière
    // seconde, et le rapport complet était réécrit 2 ou 3 fois.
    final String nextBody;
    if (prev == null) {
      nextBody = clean;
    } else if (_journalOnly(clean)) {
      nextBody = _appendJournal(prev.body, clean);
      if (nextBody == prev.body) return this;
    } else {
      final String previousSheet = _sheetOf(prev.body);
      if (previousSheet == clean) return this;
      final String journal = _journalSuffix(prev.body);
      nextBody = journal.isEmpty ? clean : clip('$clean\n$journal');
    }
    final List<AudioReportEntry> next = <AudioReportEntry>[
      AudioReportEntry(channel: key, body: nextBody, atMs: atMs),
      for (final AudioReportEntry e in entries)
        if (e.channel != key) e,
    ];
    return AudioReportBook(_fit(next));
  }

  /// Ligne écrite à part du rapport (boîte noire), pas une fiche.
  static bool isJournalLine(String line) {
    const List<String> starts = <String>[
      'Seconde ',
      'Zap :',
      'Focus audio',
      'Repli :',
      'AudioTrack ',
      'Session audio',
      'Annonces :',
      'Sonde :',
      'Arrière-plan',
      'Retour :',
      'Libération',
      'Décodeur audio :',
      'Erreur ',
    ];
    for (final String s in starts) {
      if (line.startsWith(s)) return true;
    }
    return false;
  }

  int get byteSize {
    int n = 0;
    for (final AudioReportEntry e in entries) {
      n += e.channel.length + e.body.length;
    }
    return n;
  }

  static String channelKey(String raw) {
    final String clean = redactAudioText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty || clean == '[url]') return '(sans nom)';
    if (clean.length <= 80) return clean;
    return clean.substring(0, 80);
  }

  static String clip(String body) {
    if (body.length <= maxBodyChars) return body;
    return body.substring(0, maxBodyChars);
  }

  static bool _journalOnly(String body) {
    final List<String> lines = body
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return false;
    for (final String line in lines) {
      if (!isJournalLine(line)) return false;
    }
    return true;
  }

  /// Rapport, sans les lignes de journal collées à la fin.
  static String _sheetOf(String body) {
    final List<String> kept = <String>[];
    for (final String line in body.split('\n')) {
      if (isJournalLine(line.trim())) break;
      kept.add(line);
    }
    return kept.join('\n').trim();
  }

  static String _journalSuffix(String body) {
    final List<String> kept = <String>[];
    bool seen = false;
    for (final String line in body.split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      if (isJournalLine(t)) seen = true;
      if (seen) kept.add(t);
    }
    return kept.join('\n');
  }

  static String _appendJournal(String body, String addition) {
    String current = body;
    for (final String raw in addition.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty || !isJournalLine(line)) continue;
      if (current.split('\n').any((String l) => l.trim() == line)) continue;
      current = '$current\n$line';
    }
    return clip(current);
  }

  static List<AudioReportEntry> _fit(List<AudioReportEntry> list) {
    final List<AudioReportEntry> kept = <AudioReportEntry>[];
    int bytes = 0;
    for (final AudioReportEntry e in list) {
      if (kept.length >= maxEntries) break;
      final int cost = e.channel.length + e.body.length;
      if (kept.isNotEmpty && bytes + cost > maxBytes) break;
      kept.add(e);
      bytes += cost;
    }
    return kept;
  }
}

/// Retire une adresse de flux et un secret. Le rapport n'est pas censé
/// en contenir : c'est un filet, pas un parseur d'URL.
String redactAudioText(String raw) {
  var s = raw;
  s = s.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]');
  s = s.replaceAll(RegExp(r'\b[\w.+-]+:[^@\s/]{1,80}@'), '[secret]@');
  s = s.replaceAllMapped(
    RegExp(r'(password|passwd|pwd|token|secret)=[^&\s]+', caseSensitive: false),
    (Match m) => '${m[1]}=[secret]',
  );
  return s;
}
