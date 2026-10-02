// =========================================================
//  audio_report_book_test.dart — Plafond, secret, une fiche par chaîne
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/audio_report_book.dart';

void main() {
  test('retire l\'url et le mot de passe', () {
    const String raw =
        'note password=abc token=zzz http://alice:s3cret@exemple.test/live/a.ts';
    final String clean = redactAudioText(raw);
    expect(clean.contains('s3cret'), isFalse);
    expect(clean.contains('http'), isFalse);
    expect(clean.contains('password=[secret]'), isTrue);
    expect(clean.contains('token=[secret]'), isTrue);
    expect(AudioReportBook.channelKey('http://user:secret@exemple.test/live'), '(sans nom)');
    expect(clean.contains('[url]'), isTrue);
  });

  test('une fiche par chaîne, la plus récente remplace', () {
    const AudioReportBook book = AudioReportBook.empty;
    final AudioReportBook a = book.add(channel: 'TF1', body: 'ancien', atMs: 1);
    final AudioReportBook b = a.add(channel: 'TF1', body: 'nouveau', atMs: 2);
    final AudioReportBook c = b.add(channel: 'M6', body: 'autre', atMs: 3);
    expect(c.entries.map((AudioReportEntry e) => e.channel), <String>['M6', 'TF1']);
    expect(c.entries.firstWhere((AudioReportEntry e) => e.channel == 'TF1').body, 'nouveau');
  });

  test('le plafond de taille lâche les plus anciennes', () {
    AudioReportBook book = AudioReportBook.empty;
    final String fat = 'x' * 8000;
    for (int i = 0; i < 30; i++) {
      book = book.add(channel: 'C$i', body: fat, atMs: i);
    }
    expect(book.entries.length, lessThanOrEqualTo(AudioReportBook.maxEntries));
    expect(book.byteSize, lessThanOrEqualTo(AudioReportBook.maxBytes));
    expect(book.entries.first.channel, 'C29');
    expect(book.entries.first.body.length, AudioReportBook.maxBodyChars);
  });

  test('un corps vide ne crée pas de fiche', () {
    final AudioReportBook book = AudioReportBook.empty.add(channel: 'TF1', body: '   ', atMs: 1);
    expect(book.entries, isEmpty);
  });

  test('la version courte garde les constats et jette les blocs d\'hypothèses', () {
    const String sheet = 'reçu : AAC-LC 48 kHz 2 voies · décodé par : FFmpeg · sortie : PCM 16 bits 48 kHz 2 voies\n'
        '→ Rien d\'anormal côté app\n'
        'Codec : AAC-LC (mp4a.40.2)\n'
        'Système audio : mode normal · haut-parleur d\'appel non\n'
        'Spectre > 4 kHz : non mesuré\n'
        '\n'
        '[HAUTE · CAUSE] mode_appel\n'
        'Symptôme : Le système est en mode COMMUNICATION.\n'
        'Cause : Android envoie tout le média par le chemin voix.\n'
        'Correctif : NativeVideoView.kt → applyModeRepair\n'
        'Media3 : AudioManager.setMode\n'
        'Action : Allumer « Mode : normal forcé ».\n'
        'Réglage : zuno.audio.fix.mode_normal (défaut coupé, non imposé)\n'
        '[INCERTAINE · INFO] spectre_absent\n'
        'Symptôme : Spectre coupé.\n'
        'Cause : Le réglage était coupé.\n'
        'Correctif : AudioProbeProcessor.kt\n'
        'Conclusion : 1 cause(s) sûre(s) — mode_appel.';
    final String compact = compactAudioSheet(sheet);
    expect(compact.contains('reçu : AAC-LC'), isTrue);
    expect(compact.contains('Système audio : mode normal'), isTrue);
    expect(compact.contains('[HAUTE · CAUSE] mode_appel'), isTrue);
    expect(compact.contains('Symptôme : Le système est en mode COMMUNICATION.'), isTrue);
    expect(compact.contains('Cause : Android envoie'), isTrue);
    expect(compact.contains('Conclusion : 1 cause(s) sûre(s)'), isTrue);
    expect(compact.contains('spectre_absent'), isFalse);
    expect(compact.contains('Symptôme : Spectre coupé.'), isFalse);
    expect(compact.contains('Correctif :'), isFalse);
    expect(compact.contains('Media3 :'), isFalse);
    expect(compact.contains('Action :'), isFalse);
    expect(compact.contains('Réglage :'), isFalse);
    // Idempotent : la même fiche redonne le même texte (dédoublonnage).
    expect(compactAudioSheet(sheet), compact);
  });

  test('la clé de dédoublonnage ignore la ligne « Lectures audio »', () {
    const String a = 'reçu : AAC-LC\nLectures audio sur l\'appareil : 0 — aucune\nSpectre > 4 kHz : non mesuré';
    const String b = 'reçu : AAC-LC\nLectures audio sur l\'appareil : 1 — la nôtre seulement\nSpectre > 4 kHz : non mesuré';
    expect(audioSheetDedupKey(a), audioSheetDedupKey(b));
    expect(audioSheetDedupKey(a).contains('Lectures audio'), isFalse);
    expect(audioSheetDedupKey(a).contains('Spectre'), isTrue);
  });
}
