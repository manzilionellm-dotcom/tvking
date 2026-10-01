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
}
