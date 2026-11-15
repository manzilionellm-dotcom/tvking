import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/audio_report_dedupe.dart';

/// Un rapport de son tel que le lecteur natif l'envoie (12 lignes).
String report({
  String zap = '19',
  String heard = 'Android en annonce 0',
  String path = 'flux inconnu',
}) =>
    <String>[
      'reçu : AAC-LC 24 kHz 2 voies · décodé par : FFmpeg · sortie : PCM 16 bits 48 kHz 2 voies',
      '→ Rien d\'anormal côté app (décodage complet FFmpeg).',
      'Codec : AAC-LC (mp4a.40.2)',
      'Entrée : 24 kHz, 2 voies',
      'Décodeur : FFmpeg (ffmpegLavc60.3.100-aac)',
      'Sortie : PCM 16 bits, 48 kHz, 2 voies',
      'Point de mesure : PCM 16 bits du décodeur.',
      'Effets dans l\'app : voix claire coupée, float coupé.',
      'Cycle : zap n°$zap · chaîne déjà ouverte avant (2e fois)',
      'Lectures audio : $heard, notre AudioTrack est vivant.',
      'Chemin : mode normal, $path.',
      'Conclusion : aucune cause sûre.',
    ].join('\n');

void main() {
  test('le premier rapport d\'une ouverture est écrit en entier', () {
    final AudioReportDedupe d = AudioReportDedupe();
    expect(d.linesFor(report()), hasLength(12));
  });

  test('le même rapport, sans changement : rien n\'est réécrit', () {
    final AudioReportDedupe d = AudioReportDedupe();
    d.linesFor(report());
    expect(d.linesFor(report()), isEmpty);
  });

  test('le compteur Android change : seules les lignes changées sont écrites', () {
    final AudioReportDedupe d = AudioReportDedupe();
    d.linesFor(report());
    final List<String> lines = d.linesFor(report(
      heard: 'Android en annonce 1',
      path: 'flux musique (contenu film)',
    ));
    expect(lines, hasLength(2));
    expect(lines[0], startsWith('Lectures audio : Android en annonce 1'));
    expect(lines[1], contains('flux musique'));
    // Et si ça repart dans l'autre sens, on écrit encore la différence.
    expect(d.linesFor(report()), hasLength(2));
  });

  test('une nouvelle ouverture (autre zap) repart d\'un rapport complet', () {
    final AudioReportDedupe d = AudioReportDedupe();
    d.linesFor(report(zap: '19'));
    d.linesFor(report(zap: '19', heard: 'Android en annonce 1'));
    expect(d.linesFor(report(zap: '20')), hasLength(12));
    expect(d.linesFor(report(zap: '20')), isEmpty);
  });

  test('les lignes seules (« Zap : n°19. », « Seconde 3 : … ») passent telles quelles', () {
    final AudioReportDedupe d = AudioReportDedupe();
    expect(d.linesFor('Zap : n°19.'), <String>['Zap : n°19.']);
    expect(d.linesFor('Zap : n°19.'), <String>['Zap : n°19.'],
        reason: 'ce n\'est pas un rapport : jamais retiré');
    d.linesFor(report());
    expect(d.linesFor('Seconde 3 : volume lecteur 1,0'), hasLength(1));
    // Une ligne seule ne fait pas oublier le dernier rapport.
    expect(d.linesFor(report()), isEmpty);
  });

  test('un rapport sans ligne « Cycle » (ancien lecteur) est toujours écrit en entier', () {
    final AudioReportDedupe d = AudioReportDedupe();
    final String old = report().split('\n').where((String l) => !l.startsWith('Cycle')).join('\n');
    expect(d.linesFor(old), hasLength(11));
    expect(d.linesFor(old), hasLength(11));
  });

  test('lignes vides et espaces ignorés ; reset() oublie le dernier rapport', () {
    final AudioReportDedupe d = AudioReportDedupe();
    expect(d.linesFor('\n  \n${report()}\n\n'), hasLength(12));
    d.reset();
    expect(d.linesFor(report()), hasLength(12));
  });
}
