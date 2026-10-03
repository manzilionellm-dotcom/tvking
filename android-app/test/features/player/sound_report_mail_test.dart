// =========================================================
//  sound_report_mail_test.dart — le courrier, sans appareil
// =========================================================
//  On ne peut pas ouvrir l'application e-mail ici. On vérifie
//  le texte qui lui serait donné : même nettoyage que
//  « Copier le rapport », objet, destinataire, et la coupe
//  quand le corps est trop long pour un intent.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/sound_full_report.dart';
import 'package:tv_king/features/player/domain/sound_report_mail.dart';

void main() {
  test('objet : titre, version et date', () {
    final SoundReportMail mail = SoundReportMail.compose(
      report: 'Verdict : rien',
      version: '1.2.3+99',
      date: DateTime(2026, 10, 3),
    );
    expect(mail.to, 'manzilionel.lm@gmail.com');
    expect(mail.subject, 'Rapport son Zuno 1.2.3+99 2026-10-03');
    expect(mail.mode, SoundReportMailMode.body);
    expect(mail.attachmentText, isNull);
    expect(mail.body, 'Verdict : rien');
  });

  test('version vide ou avec un saut de ligne', () {
    final SoundReportMail mail = SoundReportMail.compose(
      report: 'ok',
      version: ' \n106\r ',
      date: DateTime(2026, 1, 9),
    );
    expect(mail.subject, 'Rapport son Zuno 106 2026-01-09');
    final SoundReportMail missing = SoundReportMail.compose(
      report: 'ok',
      version: '   ',
      date: DateTime(2026, 1, 9),
    );
    expect(missing.subject, 'Rapport son Zuno inconnue 2026-01-09');
  });

  test('le corps est le même texte que Copier, secrets retirés', () {
    final SoundFullReport report = SoundFullReport.build(
      SoundReportFacts(
        channelName: 'France 24',
        channelBody: 'flux https://cdn.example/live/a.ts user:s3cret@host '
            'password=s3cret',
        witnessBody: 'témoin',
        answers: const SoundAnswers(),
        channelWasLive: false,
      ),
    );
    final SoundReportMail mail = SoundReportMail.compose(
      report: report.text,
      version: '106',
      date: DateTime(2026, 10, 3),
    );
    expect(mail.mode, SoundReportMailMode.body);
    expect(mail.body, report.text);
    expect(mail.body.contains('s3cret'), isFalse);
    expect(mail.body.contains('cdn.example'), isFalse);
    expect(mail.body.contains('http'), isFalse);
    expect(mail.body.contains('password=s3cret'), isFalse);
    expect(mail.body, contains('[url]'));
    expect(mail.body, contains('password=[secret]'));
    expect(utf8.encode(mail.body).length <= SoundReportMail.intentBodyMaxBytes,
        isTrue);
  });

  test('un rapport de 12 000 caractères tient dans le corps', () {
    final String text = 'début\n${'a' * 11990}';
    expect(text.length, greaterThan(12000 - 20));
    expect(text.length, lessThan(SoundReportMail.intentBodyMaxBytes));
    final SoundReportMail mail = SoundReportMail.compose(
      report: text,
      version: '1',
      date: DateTime(2026, 10, 3),
    );
    expect(mail.mode, SoundReportMailMode.body);
    expect(mail.body, text);
    expect(mail.attachmentText, isNull);
  });

  test('corps trop long : fichier entier, début coupé à une ligne', () {
    final List<String> lines = List<String>.generate(
      4000,
      (int i) => 'Ligne ${i.toString().padLeft(4, '0')} le verdict est au début',
    );
    final String text = lines.join('\n');
    expect(utf8.encode(text).length, greaterThan(SoundReportMail.intentBodyMaxBytes));
    final SoundReportMail mail = SoundReportMail.compose(
      report: text,
      version: '1',
      date: DateTime(2026, 10, 3),
    );
    expect(mail.mode, SoundReportMailMode.attachment);
    expect(mail.attachmentText, text);
    expect(mail.body.startsWith('Ligne 0000'), isTrue);
    expect(mail.body, contains(SoundReportMail.attachedNote.trim()));
    expect(
      utf8.encode(mail.body).length,
      lessThanOrEqualTo(SoundReportMail.previewMaxBytes),
    );
    final String head = mail.body.split(SoundReportMail.attachedNote).first;
    expect(text.startsWith(head), isTrue);
    expect(head.contains('\n'), isTrue);
    for (final String line in head.split('\n')) {
      expect(lines, contains(line));
    }
    expect(head.contains(lines.last), isFalse);
    expect(mail.body.contains('s3cret'), isFalse);
  });

  test('sans fichier possible : on tronque, le début reste entier', () {
    final String text = List<String>.generate(
      80,
      (int i) => 'Bloc $i complet',
    ).join('\n');
    final SoundReportMail mail = SoundReportMail.compose(
      report: text,
      version: '1',
      date: DateTime(2026, 10, 3),
      maxBodyBytes: 400,
      allowAttachment: false,
    );
    expect(mail.mode, SoundReportMailMode.body);
    expect(mail.attachmentText, isNull);
    expect(mail.body.startsWith('Bloc 0 complet'), isTrue);
    expect(mail.body, contains(SoundReportMail.truncatedNote.trim()));
    expect(utf8.encode(mail.body).length, lessThanOrEqualTo(400));
    final String head = mail.body.split(SoundReportMail.truncatedNote).first;
    expect(text.startsWith(head), isTrue);
    expect(head.endsWith('complet'), isTrue);
    expect(mail.body.contains('Bloc 79'), isFalse);
  });

  test('une ligne géante est coupée sur un caractère, pas au milieu d\'un accent', () {
    final String text = 'é' * 5000;
    final SoundReportMail mail = SoundReportMail.compose(
      report: text,
      version: '1',
      date: DateTime(2026, 10, 3),
      maxBodyBytes: 100,
      previewMaxBytes: 50,
      allowAttachment: true,
    );
    expect(mail.mode, SoundReportMailMode.attachment);
    expect(mail.attachmentText, text);
    expect(utf8.encode(mail.body).length, lessThanOrEqualTo(50));
    // Chaque « é » fait 2 octets. Le début décodé ne doit pas être cassé.
    utf8.encode(mail.body);
    expect(mail.body.contains('\uFFFD'), isFalse);
  });

  test('le filet est le même la deuxième fois', () {
    const String dirty = 'voir https://x.test/a password=abc user:secret@h';
    final SoundReportMail once = SoundReportMail.compose(
      report: dirty,
      version: '1',
      date: DateTime(2026, 10, 3),
    );
    final SoundReportMail twice = SoundReportMail.compose(
      report: once.body,
      version: '1',
      date: DateTime(2026, 10, 3),
    );
    expect(twice.body, once.body);
    expect(once.body.contains('abc'), isFalse);
    expect(once.body.contains('secret@'), isFalse);
    expect(once.body, contains('[url]'));
    expect(once.body, contains('password=[secret]'));
    expect(once.body, contains('[secret]@'));
  });

  test('après un intent trop gros, le second essai raccourcit', () {
    final String text = 'Debut du verdict\n${'x' * 3000}\nfin';
    final SoundReportMail shrunk = SoundReportMail.shrink(
      report: text,
      version: '2',
      date: DateTime(2026, 10, 3),
      allowAttachment: true,
    );
    expect(shrunk.mode, SoundReportMailMode.attachment);
    expect(shrunk.attachmentText, text);
    expect(shrunk.body.startsWith('Debut du verdict'), isTrue);
    expect(utf8.encode(shrunk.body).length, lessThanOrEqualTo(2048));
    final SoundReportMail noFile = SoundReportMail.shrink(
      report: text,
      version: '2',
      date: DateTime(2026, 10, 3),
      allowAttachment: false,
    );
    expect(noFile.attachmentText, isNull);
    expect(noFile.body.startsWith('Debut du verdict'), isTrue);
    expect(noFile.body, contains('début est complet'));
    expect(utf8.encode(noFile.body).length, lessThanOrEqualTo(2048));
  });

  test('les mots du natif', () {
    expect(
      SoundReportMail.fromNative('opened').status,
      SoundReportMailStatus.opened,
    );
    expect(
      SoundReportMail.fromNative('no_app').message,
      contains('Aucune application e-mail'),
    );
    expect(
      SoundReportMail.fromNative('too_large').status,
      SoundReportMailStatus.error,
    );
    expect(
      SoundReportMail.fromNative(null).message,
      contains('presse-papiers'),
    );
    expect(
      SoundReportMail.fromNative('empty').status,
      SoundReportMailStatus.empty,
    );
  });

  test('le plugin vise la même adresse et ne contient pas de secret', () {
    final String kt = File(
      'packages/zuno_mail/android/src/main/kotlin/com/manzilionellm/zuno_mail/ZunoMailPlugin.kt',
    ).readAsStringSync();
    final String manifest = File(
      'packages/zuno_mail/android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(kt.contains(SoundReportMail.recipient), isTrue);
    expect(kt.contains('ACTION_SENDTO'), isTrue);
    expect(kt.contains('ACTION_SEND'), isTrue);
    expect(kt.contains('FileProvider'), isTrue);
    expect(kt.contains('no_app'), isTrue);
    final String lower = kt.toLowerCase();
    expect(lower.contains('smtp'), isFalse);
    expect(lower.contains('api_key'), isFalse);
    expect(lower.contains('apikey'), isFalse);
    expect(lower.contains('password'), isFalse);
    expect(lower.contains('bearer '), isFalse);
    expect(manifest.contains('mailto'), isTrue);
    expect(manifest.contains('INTERNET'), isFalse);
  });
}
