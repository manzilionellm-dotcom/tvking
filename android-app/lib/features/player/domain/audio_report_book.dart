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
    final List<AudioReportEntry> next = <AudioReportEntry>[
      AudioReportEntry(channel: key, body: clean, atMs: atMs),
      for (final AudioReportEntry e in entries)
        if (e.channel != key) e,
    ];
    return AudioReportBook(_fit(next));
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

/// Version courte d'une fiche pour la boîte noire : on garde les constats
/// (reçu / décodé / sortie, verdicts, cycle, système audio, lectures,
/// spectre, stéréo, causes SÛRES avec symptôme et cause) et on retire les
/// blocs « [INCERTAINE · INFO] » (hypothèses réécrites à chaque ouverture :
/// bruit, pas information) et les lignes de mode d'emploi (Correctif /
/// Media3 / Action / Réglage). La fiche complète reste dans Réglages →
/// Diagnostic du son. Fonction pure, testée.
String compactAudioSheet(String sheet) {
  final List<String> out = <String>[];
  bool skippingBlock = false;
  for (final String raw in sheet.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[')) {
      skippingBlock = line.startsWith('[INCERTAINE · INFO]');
      if (skippingBlock) continue;
    } else if (line.startsWith('Conclusion :')) {
      skippingBlock = false;
    }
    if (skippingBlock) continue;
    if (line.startsWith('Correctif :') ||
        line.startsWith('Media3 :') ||
        line.startsWith('Action :') ||
        line.startsWith('Réglage :')) {
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}
