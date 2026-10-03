// =========================================================
//  sound_full_report.dart — Un seul texte, un seul verdict
// =========================================================
//  Le client n'est pas développeur. Ce fichier ne joue rien et ne
//  change aucun interrupteur : il LIT des fiches déjà écrites par le
//  lecteur, les réponses en un mot, et les lignes ajoutées par les
//  autres angles, puis il rend UN texte copiable.
//
//  Quatre verdicts, dans cet ordre (le premier qui s'allume gagne) :
//    1. chemin d'appel détecté  — Android fait passer le son comme
//       un téléphone (mode appel, Bluetooth d'appel, écouteur) ;
//    2. phase inversée          — gauche ≈ −droite, la voix du
//       centre s'annule (« dans un trou ») ;
//    3. source étroite          — la chaîne a peu d'aigus, le son
//       témoin (bruit) en a : le lecteur sait sortir un son large ;
//    4. rien d'anormal côté app — aucune de ces trois preuves.
//
//  Les seuils sont les MÊMES chiffres que le lecteur
//  (AudioSpectrum 0,40 / 0,12 et AudioPhase −0,70). On ne les
//  invente pas ici : une voix à 3 % au-dessus de 4 kHz n'est PAS,
//  à elle seule, un défaut. Il faut le témoin large pour dire
//  « source étroite ».
//
//  Objet pur : testé sans box, sans flux, sans disque.
// =========================================================

import 'audio_report_book.dart';

/// Ce que la personne entend, en un mot. Null = elle n'a pas répondu.
enum SoundEar { clair, sourd }

/// Oui / non. Null = pas répondu. On ne devine pas.
enum SoundYes { oui, non }

/// Les trois questions. Chacune peut rester vide.
class SoundAnswers {
  const SoundAnswers({this.ear, this.bluetooth, this.otherApp});

  final SoundEar? ear;
  final SoundYes? bluetooth;
  final SoundYes? otherApp;

  static const SoundAnswers unanswered = SoundAnswers();
}

/// Bande lue sur une fiche. [unknown] = pas de chiffre : on ne tranche pas.
enum SoundBand { wide, low, mid, unknown }

enum SoundVerdict { callPath, invertedPhase, narrowSource, appClear }

enum SoundConfidence { high, mid, low }

/// Tout ce que le bouton a rassemblé. Pas d'URL : le nom de chaîne
/// est déjà passé par [AudioReportBook.channelKey] à l'affichage.
class SoundReportFacts {
  const SoundReportFacts({
    required this.channelName,
    required this.channelBody,
    required this.witnessBody,
    required this.answers,
    required this.channelWasLive,
    this.extraLines = const <String>[],
  });

  /// Nom affiché. Vide = aucune chaîne connue.
  final String channelName;

  /// Fiche de la chaîne (rapport du lecteur + journal).
  final String channelBody;

  /// Fiche du son témoin, joué après la chaîne.
  final String witnessBody;

  final SoundAnswers answers;

  /// Vrai seulement si le lecteur de la chaîne tournait encore
  /// pendant les 10 secondes. Faux = on a repris la dernière fiche.
  final bool channelWasLive;

  /// Lignes qui ne sont ni une fiche ni un journal (un autre angle
  /// a émis une phrase courte). Le registre [SoundReportExtensions]
  /// s'y ajoute au moment du texte.
  final List<String> extraLines;

  SoundReportFacts copyWith({
    SoundAnswers? answers,
    List<String>? extraLines,
    bool? channelWasLive,
  }) {
    return SoundReportFacts(
      channelName: channelName,
      channelBody: channelBody,
      witnessBody: witnessBody,
      answers: answers ?? this.answers,
      channelWasLive: channelWasLive ?? this.channelWasLive,
      extraLines: extraLines ?? this.extraLines,
    );
  }
}

/// Une ligne d'un autre angle. [id] est unique : un second [register]
/// avec le même id REMPLACE le premier (un fichier importé deux fois
/// n'écrit pas la ligne en double).
class SoundReportExtension {
  const SoundReportExtension({required this.id, required this.lines});

  final String id;

  /// [facts] est le relevé déjà rassemblé. On renvoie des phrases
  /// courtes, sans URL et sans mot de passe.
  final List<String> Function(SoundReportFacts facts) lines;
}

/// Point d'accroche. Les autres angles appellent [register] depuis
/// LEUR fichier. Ils n'éditent pas le verdict.
///
/// Ce qui change le verdict, dans ces lignes-là :
///   • « chemin d'appel », « écouteur d'appel », « Bluetooth appel allumé » ;
///   • « voies opposées », ou une corrélation ≤ −0,70.
/// Une ligne « Spectre… » ajoutée ici est montrée, elle ne remplace
/// pas la fiche de la chaîne ni celle du témoin.
class SoundReportExtensions {
  SoundReportExtensions._();

  static final Map<String, SoundReportExtension> _items =
      <String, SoundReportExtension>{};

  static void register(SoundReportExtension ext) {
    final String id = ext.id.trim();
    if (id.isEmpty) return;
    _items[id] = ext;
  }

  static void unregister(String id) {
    _items.remove(id);
  }

  /// Réservé aux tests : repart d'un registre vide.
  static void debugReset() {
    _items.clear();
  }

  static List<String> collect(SoundReportFacts facts) {
    final List<String> ids = _items.keys.toList()..sort();
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final String id in ids) {
      final SoundReportExtension? ext = _items[id];
      if (ext == null) continue;
      List<String> lines;
      try {
        lines = ext.lines(facts);
      } catch (_) {
        // Un angle cassé ne doit pas empêcher le client de copier.
        continue;
      }
      for (final String raw in lines) {
        final String t = raw.trim();
        if (t.isEmpty || !seen.add(t)) continue;
        out.add(t);
      }
    }
    return out;
  }
}

/// Durées du geste. 10 s de chaîne (si elle joue) + 10 s de témoin.
/// Le fichier témoin dure 10,000 s : on ne le coupe pas avant la fin,
/// et on ne dépasse pas 30 s.
class SoundReportPlan {
  const SoundReportPlan({
    required this.channelListen,
    required this.witnessPlay,
  });

  final Duration channelListen;
  final Duration witnessPlay;

  static const Duration channelWindow = Duration(seconds: 10);
  static const Duration witnessWindow = Duration(seconds: 10);
  static const Duration budget = Duration(seconds: 30);

  factory SoundReportPlan.forCapture({required bool channelLive}) {
    return SoundReportPlan(
      channelListen: channelLive ? channelWindow : Duration.zero,
      witnessPlay: witnessWindow,
    );
  }

  Duration get total => channelListen + witnessPlay;

  bool get withinBudget => total <= budget;
}

/// Accumule les phrases pendant le geste, sans les mélanger.
///
/// Une fiche complète (elle contient « Codec : » ou « Conclusion : »)
/// REMPLACE la fiche de la cible. Une ligne de journal s'AJOUTE.
/// Tout le reste va dans [loose] : un autre angle peut émettre une
/// phrase courte sans effacer la fiche.
class SoundReportCapture {
  String channelSheet = '';
  String witnessSheet = '';
  final List<String> channelJournal = <String>[];
  final List<String> witnessJournal = <String>[];
  final List<String> loose = <String>[];

  /// Dernière fiche déjà sur le disque. On ne l'écrase pas si une
  /// fiche plus fraîche est déjà arrivée.
  void seedChannel(String body) {
    if (channelSheet.trim().isEmpty) channelSheet = body.trim();
  }

  /// Fiche témoin déjà écrite par le lecteur, si l'écoute en direct
  /// n'a pas eu le temps de la renvoyer. Même règle : on ne l'écrase pas.
  void seedWitness(String body) {
    if (witnessSheet.trim().isEmpty) witnessSheet = body.trim();
  }

  void add(String raw, {required bool witness}) {
    final String safe = redactAudioText(raw).trim();
    if (safe.isEmpty) return;
    final List<String> lines = _linesOf(safe);
    if (lines.isEmpty) return;
    if (lines.every(AudioReportBook.isJournalLine)) {
      final List<String> dest = witness ? witnessJournal : channelJournal;
      for (final String line in lines) {
        if (!dest.contains(line)) dest.add(line);
      }
      return;
    }
    if (safe.contains('Codec :') || safe.contains('Conclusion :')) {
      if (witness) {
        witnessSheet = safe;
      } else {
        channelSheet = safe;
      }
      return;
    }
    for (final String line in lines) {
      if (!loose.contains(line)) loose.add(line);
    }
  }

  String get channelBody => _join(channelSheet, channelJournal);

  String get witnessBody => _join(witnessSheet, witnessJournal);
}

class SoundFullReport {
  const SoundFullReport({
    required this.verdict,
    required this.confidence,
    required this.text,
  });

  final SoundVerdict verdict;
  final SoundConfidence confidence;
  final String text;

  String get verdictLabel => labelOf(verdict);

  static String labelOf(SoundVerdict verdict) {
    switch (verdict) {
      case SoundVerdict.callPath:
        return "chemin d'appel détecté";
      case SoundVerdict.invertedPhase:
        return 'phase inversée';
      case SoundVerdict.narrowSource:
        return 'source étroite';
      case SoundVerdict.appClear:
        return "rien d'anormal côté app";
    }
  }

  static String confidenceLabel(SoundConfidence confidence) {
    switch (confidence) {
      case SoundConfidence.high:
        return 'haute';
      case SoundConfidence.mid:
        return 'moyenne';
      case SoundConfidence.low:
        return 'basse';
    }
  }

  /// Texte unique. Les secrets sont retirés encore une fois à la fin.
  static SoundFullReport build(SoundReportFacts facts) {
    final List<String> extras = _unique(<String>[
      ...facts.extraLines,
      ...SoundReportExtensions.collect(facts),
    ]);
    final _Read channel = _read(facts.channelBody);
    final _Read witness = _read(facts.witnessBody);
    final _Read extra = _read(extras.join('\n'));

    final bool call = channel.call || witness.call || extra.call;
    final bool phase = channel.phase || witness.phase || extra.phase;
    final bool narrow = _narrow(channel, witness);

    final SoundVerdict verdict;
    if (call) {
      verdict = SoundVerdict.callPath;
    } else if (phase) {
      verdict = SoundVerdict.invertedPhase;
    } else if (narrow) {
      verdict = SoundVerdict.narrowSource;
    } else {
      verdict = SoundVerdict.appClear;
    }

    final bool callMeasured = channel.call || witness.call;
    final bool phaseMeasured = channel.phase || witness.phase;
    SoundConfidence confidence = _baseConfidence(
      verdict: verdict,
      channel: channel,
      witness: witness,
      callMeasured: callMeasured,
      phaseMeasured: phaseMeasured,
      hasChannelText: facts.channelBody.trim().isNotEmpty,
    );
    confidence = _withAnswers(confidence, verdict, facts.answers);

    final String text = _render(
      facts: facts,
      extras: extras,
      channel: channel,
      witness: witness,
      verdict: verdict,
      confidence: confidence,
      call: call,
      phase: phase,
      narrow: narrow,
    );
    return SoundFullReport(
      verdict: verdict,
      confidence: confidence,
      text: text,
    );
  }
}

// ---------------------------------------------------------------------
//  Seuils — les mêmes chiffres que le lecteur, recopiés pour que ce
//  fichier n'ait pas besoin d'Android. Si le lecteur change un seuil,
//  le test de ce fichier doit changer avec, exprès.
// ---------------------------------------------------------------------

/// AudioSpectrum.WIDE_MIN_RATIO. Au-dessus, le son a des aigus.
const double _wideMin = 0.40;

/// AudioSpectrum.LOW_MAX_RATIO. En dessous, la bande haute est basse.
/// Une voix naturelle tombe ici : ce n'est pas une preuve tout seul.
const double _lowMax = 0.12;

/// AudioPhase.INVERT_MAX. En dessous, les voies s'opposent.
const double _invertMax = -0.70;

const int _maxChars = 12000;

class _Read {
  bool call = false;
  bool phase = false;
  double? correlation;
  SoundBand header = SoundBand.unknown;
  SoundBand decoder = SoundBand.unknown;
  double? recent;
  bool sourceMarker = false;
  bool hasChemin = false;
  bool hasSpectrum = false;
  final List<String> lines = <String>[];

  /// Bande de la chaîne : le cumul (une voix reste basse), pas la
  /// dernière seconde (un jingle peut être large une seconde).
  SoundBand get channelBand {
    if (header != SoundBand.unknown) return header;
    return decoder;
  }

  /// Bande du témoin : la dernière seconde est le bruit (les 5 dernières
  /// secondes du fichier). Le cumul mélange la voix, qui est étroite,
  /// et le bruit, qui est large : la dernière seconde tranche.
  SoundBand get witnessBand {
    if (recent != null) return _bandFromRatio(recent!);
    if (header != SoundBand.unknown) return header;
    return decoder;
  }
}

bool _narrow(_Read channel, _Read witness) {
  final SoundBand c = channel.channelBand;
  final SoundBand w = witness.witnessBand;
  if (c == SoundBand.low && w == SoundBand.wide) return true;
  // Mono, débit bas, fréquence basse : la fiche le dit déjà.
  // On ne le croit que si le témoin n'est pas étroit lui aussi
  // (sinon l'appareil peut être la cause, pas la chaîne).
  if (channel.sourceMarker && c != SoundBand.wide && w != SoundBand.low) {
    return true;
  }
  return false;
}

SoundConfidence _baseConfidence({
  required SoundVerdict verdict,
  required _Read channel,
  required _Read witness,
  required bool callMeasured,
  required bool phaseMeasured,
  required bool hasChannelText,
}) {
  switch (verdict) {
    case SoundVerdict.callPath:
      return callMeasured ? SoundConfidence.high : SoundConfidence.mid;
    case SoundVerdict.invertedPhase:
      return phaseMeasured ? SoundConfidence.high : SoundConfidence.mid;
    case SoundVerdict.narrowSource:
      if (channel.channelBand == SoundBand.low &&
          witness.witnessBand == SoundBand.wide) {
        return SoundConfidence.high;
      }
      if (witness.witnessBand == SoundBand.wide) return SoundConfidence.mid;
      return SoundConfidence.low;
    case SoundVerdict.appClear:
      if (channel.channelBand == SoundBand.wide &&
          channel.hasChemin &&
          !channel.call &&
          !witness.phase) {
        return SoundConfidence.high;
      }
      if (channel.channelBand == SoundBand.low &&
          witness.witnessBand == SoundBand.low) {
        return SoundConfidence.low;
      }
      if (!hasChannelText &&
          witness.header == SoundBand.unknown &&
          witness.recent == null) {
        return SoundConfidence.low;
      }
      return SoundConfidence.mid;
  }
}

SoundConfidence _withAnswers(
  SoundConfidence base,
  SoundVerdict verdict,
  SoundAnswers answers,
) {
  SoundConfidence c = base;
  if (verdict == SoundVerdict.callPath) {
    if (answers.bluetooth == SoundYes.oui) c = _raise(c);
    if (answers.bluetooth == SoundYes.non) c = _lower(c);
  }
  if (verdict == SoundVerdict.narrowSource) {
    if (answers.ear == SoundEar.sourd) c = _raise(c);
    if (answers.ear == SoundEar.clair) c = _lower(c);
  }
  if (verdict == SoundVerdict.invertedPhase) {
    // « Deux sons qui se battent » peut être une autre app, pas
    // seulement des voies inversées. On baisse d'un cran.
    if (answers.otherApp == SoundYes.oui) c = _lower(c);
  }
  if (verdict == SoundVerdict.appClear) {
    if (answers.ear == SoundEar.clair) c = _raise(c);
    if (answers.ear == SoundEar.sourd) c = _lower(c);
    if (answers.otherApp == SoundYes.oui) c = _lower(c);
  }
  return c;
}

SoundConfidence _raise(SoundConfidence c) {
  switch (c) {
    case SoundConfidence.low:
      return SoundConfidence.mid;
    case SoundConfidence.mid:
      return SoundConfidence.high;
    case SoundConfidence.high:
      return SoundConfidence.high;
  }
}

SoundConfidence _lower(SoundConfidence c) {
  switch (c) {
    case SoundConfidence.high:
      return SoundConfidence.mid;
    case SoundConfidence.mid:
      return SoundConfidence.low;
    case SoundConfidence.low:
      return SoundConfidence.low;
  }
}

_Read _read(String body) {
  final _Read r = _Read();
  for (final String line in _linesOf(body)) {
    r.lines.add(line);
    if (_lineSaysCall(line)) r.call = true;
    if (line.contains('voies opposées')) r.phase = true;
    final double? corr = _correlation(line);
    if (corr != null) {
      if (r.correlation == null || corr < r.correlation!) r.correlation = corr;
      if (corr <= _invertMax) r.phase = true;
    }
    if (line.startsWith('Chemin :')) r.hasChemin = true;
    if (line.startsWith('Spectre > 4 kHz')) {
      r.hasSpectrum = true;
      r.header = _bandWord(line);
      if (r.header == SoundBand.unknown) {
        final double? ratio = _firstPercent(line);
        if (ratio != null) r.header = _bandFromRatio(ratio);
      }
    }
    if (line.startsWith('Dernière seconde') ||
        line.startsWith('Derniere seconde')) {
      r.recent = _firstPercent(line);
    }
    final String stage = line.replaceFirst(RegExp(r'^-\s*'), '');
    if (stage.startsWith('decodeur :')) {
      r.decoder = _bandWord(stage);
    }
    if (_sourceMarker(line)) r.sourceMarker = true;
  }
  return r;
}

bool _lineSaysCall(String line) {
  final String l = line.toLowerCase();
  if (l.contains('pas de chemin') || l.contains('sans chemin')) return false;
  if (l.contains("chemin d'appel")) return true;
  if (l.contains("écouteur d'appel") || l.contains("ecouteur d'appel")) {
    return true;
  }
  if (l.contains('bluetooth appel allumé') ||
      l.contains('bluetooth appel allume')) {
    return true;
  }
  return false;
}

bool _sourceMarker(String line) {
  if (line.startsWith('SOURCE :')) return true;
  final String l = line.toLowerCase();
  return l.contains('source_mono') ||
      l.contains('source_basse_freq') ||
      l.contains('debit_faible');
}

SoundBand _bandWord(String line) {
  final int colon = line.indexOf(':');
  final String after = (colon >= 0 ? line.substring(colon + 1) : line)
      .toLowerCase();
  if (after.contains('trop basse') ||
      after.contains('trop court') ||
      after.contains('silence') ||
      after.contains('pas assez') ||
      after.contains('trop faible') ||
      after.contains('sonde coupée') ||
      after.contains('sonde coupee')) {
    return SoundBand.unknown;
  }
  if (after.contains('présent') || after.contains('present'))
    return SoundBand.wide;
  if (after.trimLeft().startsWith('bas')) return SoundBand.low;
  if (after.contains('intermédiaire') || after.contains('intermediaire')) {
    return SoundBand.mid;
  }
  if (after.contains('large')) return SoundBand.wide;
  if (after.contains('basse')) return SoundBand.low;
  return SoundBand.unknown;
}

SoundBand _bandFromRatio(double ratio) {
  if (ratio >= _wideMin) return SoundBand.wide;
  if (ratio <= _lowMax) return SoundBand.low;
  return SoundBand.mid;
}

final RegExp _pctRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*%');

double? _firstPercent(String line) {
  final Match? m = _pctRe.firstMatch(line);
  if (m == null) return null;
  final double? v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (v == null) return null;
  return v / 100.0;
}

/// « Corrélation gauche/droite (1 s, copie) : -0,95 » ou « G/D -0,85 ».
final RegExp _corrRe = RegExp(
  r'(?:Corr[ée]lation gauche/droite|G/D)\s*(?:\([^)]*\))?\s*:?\s*([+−-]?\d+(?:[.,]\d+)?)',
);

double? _correlation(String line) {
  final Match? m = _corrRe.firstMatch(line);
  if (m == null) return null;
  final String raw = m.group(1)!.replaceAll('−', '-').replaceAll(',', '.');
  return double.tryParse(raw);
}

String _render({
  required SoundReportFacts facts,
  required List<String> extras,
  required _Read channel,
  required _Read witness,
  required SoundVerdict verdict,
  required SoundConfidence confidence,
  required bool call,
  required bool phase,
  required bool narrow,
}) {
  final StringBuffer b = StringBuffer();
  b.writeln('RAPPORT SON COMPLET');
  b.writeln('');
  b.writeln('Verdict : ${SoundFullReport.labelOf(verdict)}');
  b.writeln('Confiance : ${SoundFullReport.confidenceLabel(confidence)}');
  b.writeln('');
  b.writeln('Ce que ça veut dire :');
  b.writeln(
    _meaning(
      verdict: verdict,
      channel: channel,
      witness: witness,
      answers: facts.answers,
      call: call,
    ),
  );
  final List<String> aussi = <String>[];
  if (verdict != SoundVerdict.invertedPhase && phase) {
    aussi.add('phase inversée');
  }
  if (verdict != SoundVerdict.narrowSource &&
      verdict != SoundVerdict.callPath &&
      narrow) {
    aussi.add('source étroite');
  }
  if (aussi.isNotEmpty) {
    b.writeln('');
    b.writeln('Aussi noté : ${aussi.join(', ')}.');
  }
  b.writeln('');
  b.writeln('Vous avez dit :');
  b.writeln('- son : ${_earWord(facts.answers.ear)}');
  b.writeln('- Bluetooth : ${_yesWord(facts.answers.bluetooth)}');
  b.writeln(
    "- autre application qui joue : ${_yesWord(facts.answers.otherApp)}",
  );
  if (facts.answers.bluetooth == SoundYes.oui && !call) {
    b.writeln(
      "Bluetooth oui. La box ne montre pas un chemin d'appel "
      "(le Bluetooth musique n'est pas un appel).",
    );
  }
  if (facts.answers.otherApp == SoundYes.oui) {
    b.writeln(
      "Vous avez dit qu'une autre application joue du son. "
      "Ça peut faire deux sons qui se battent. Ce rapport ne la coupe pas.",
    );
  }
  b.writeln('');
  b.writeln('Système :');
  for (final String line in _systemLines(channel, witness)) {
    b.writeln(line);
  }
  b.writeln('');
  b.writeln(_channelHeading(facts));
  final Set<String> shown = <String>{};
  for (final String line in _detailLines(channel.lines)) {
    if (!shown.add(line)) continue;
    b.writeln(line);
  }
  if (channel.lines.isEmpty) {
    b.writeln('Pas de fiche pour la chaîne.');
  }
  b.writeln('');
  b.writeln('Son témoin (10 secondes, voix puis bruit) :');
  final List<String> witnessOnly = <String>[];
  int shared = 0;
  for (final String line in _detailLines(witness.lines)) {
    if (shown.contains(line)) {
      shared++;
      continue;
    }
    if (witnessOnly.contains(line)) continue;
    witnessOnly.add(line);
  }
  if (witness.lines.isEmpty) {
    b.writeln('Le témoin n\'a pas encore de fiche.');
  } else {
    if (shared > 0) {
      b.writeln('Lignes identiques à la chaîne, non recopiées : $shared.');
    }
    for (final String line in witnessOnly) {
      b.writeln(line);
    }
    if (witnessOnly.isEmpty && shared > 0) {
      b.writeln('Rien de plus que la chaîne.');
    }
  }
  if (extras.isNotEmpty) {
    b.writeln('');
    b.writeln('Ajouts :');
    for (final String line in extras) {
      if (shown.contains(line)) continue;
      b.writeln(line);
    }
  }
  b.writeln('');
  b.writeln("Rien n'est envoyé. Copiez ce texte et transmettez-le.");
  final String clean = redactAudioText(b.toString().trim());
  if (clean.length <= _maxChars) return clean;
  return '${clean.substring(0, _maxChars)}\n… texte coupé (trop long pour un copier-coller).';
}

String _meaning({
  required SoundVerdict verdict,
  required _Read channel,
  required _Read witness,
  required SoundAnswers answers,
  required bool call,
}) {
  switch (verdict) {
    case SoundVerdict.callPath:
      return "Android envoie le son par le chemin d'un appel "
          '(bande étroite, comme au téléphone). Ce n\'est pas un filtre de Zuno. '
          "Coupez l'appel, le Bluetooth d'appel, ou l'application qui tient le micro, "
          'puis relancez ce rapport.';
    case SoundVerdict.invertedPhase:
      return 'Les voies gauche et droite s\'opposent : une voix au centre '
          "s'annule, le son tombe dans un trou. Ce n'est pas un manque d'aigus.";
    case SoundVerdict.narrowSource:
      return 'La chaîne a peu d\'aigus. Le son témoin, lui, en a. '
          'Zuno sait donc sortir un son large : le son étroit vient de la chaîne, '
          "pas d'un filtre de l'app.";
    case SoundVerdict.appClear:
      if (channel.channelBand == SoundBand.low &&
          witness.witnessBand == SoundBand.low) {
        return "Rien dans l'app n'explique le défaut (pas de chemin d'appel, "
            "pas de voies opposées). Mais la chaîne et le témoin sont étroits : "
            "l'appareil peut encore colorer le son après l'app. Ce n'est pas tranché.";
      }
      if (channel.channelBand == SoundBand.unknown) {
        return "Rien dans l'app n'explique le défaut avec les chiffres présents. "
            "Les aigus de la chaîne n'ont pas été mesurés (spectre coupé ou chaîne "
            'déjà fermée). Allumez « Spectre », regardez la chaîne quelques secondes, '
            'puis relancez ce bouton.';
      }
      final String ear = answers.ear == SoundEar.sourd
          ? ' Vous entendez sourd, les mesures de l\'app ne montrent pas un filtre.'
          : '';
      return "Les mesures de l'app ne montrent pas un chemin d'appel, "
          "ni des voies opposées, ni une chaîne étroite alors que le témoin est large. "
          "Si le son reste mauvais, le défaut n'est pas un filtre dans Zuno.$ear";
  }
}

const List<String> _systemPrefixes = <String>[
  'Chemin :',
  'Lectures audio',
  'Effets dans l\'app',
  'Focus audio',
];

List<String> _systemLines(_Read channel, _Read witness) {
  String pick(String prefix, String missing) {
    for (final String line in channel.lines) {
      if (line.startsWith(prefix)) return line;
    }
    for (final String line in witness.lines) {
      if (line.startsWith(prefix)) return line;
    }
    return missing;
  }

  return <String>[
    pick('Chemin :', 'Chemin : pas encore lu.'),
    pick('Lectures audio', 'Lectures : pas encore lu.'),
    pick('Effets dans l\'app', 'Effets : pas encore lu.'),
    if (pick('Focus audio', '') != '') pick('Focus audio', ''),
  ];
}

bool _isSystemLine(String line) {
  for (final String prefix in _systemPrefixes) {
    if (line.startsWith(prefix)) return true;
  }
  return false;
}

List<String> _detailLines(List<String> lines) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String line in lines) {
    if (_isSystemLine(line)) continue;
    if (!seen.add(line)) continue;
    out.add(line);
  }
  return out;
}

String _channelHeading(SoundReportFacts facts) {
  final String name = facts.channelName.trim().isEmpty
      ? 'aucune'
      : AudioReportBook.channelKey(facts.channelName);
  if (facts.channelWasLive) {
    return 'Chaîne : $name — écoutée 10 secondes pendant ce rapport.';
  }
  return 'Chaîne : $name — pas ouverte pendant ce rapport. '
      'Dernière fiche conservée (pas les 10 secondes en direct).';
}

String _earWord(SoundEar? ear) {
  switch (ear) {
    case SoundEar.clair:
      return 'clair';
    case SoundEar.sourd:
      return 'sourd';
    case null:
      return 'pas dit';
  }
}

String _yesWord(SoundYes? v) {
  switch (v) {
    case SoundYes.oui:
      return 'oui';
    case SoundYes.non:
      return 'non';
    case null:
      return 'pas dit';
  }
}

List<String> _linesOf(String body) {
  return <String>[
    for (final String raw in body.split('\n'))
      if (raw.trim().isNotEmpty) raw.trim(),
  ];
}

List<String> _unique(Iterable<String> lines) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String raw in lines) {
    final String t = raw.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
  }
  return out;
}

String _join(String sheet, List<String> journal) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String line in _linesOf(sheet)) {
    if (seen.add(line)) out.add(line);
  }
  for (final String line in journal) {
    final String t = line.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
  }
  return out.join('\n');
}
