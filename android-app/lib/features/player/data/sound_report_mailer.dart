// =========================================================
//  sound_report_mailer.dart — Ouvre l'application e-mail
// =========================================================
//  Aucun envoi depuis Zuno. On demande à Android d'ouvrir
//  l'application qui sait lire un mailto. S'il n'y en a pas
//  (cas fréquent sur une box), on répond « no_app » : l'écran
//  copie le rapport et propose d'enregistrer un fichier.
//
//  Le canal est enregistré par le plugin zuno_mail, qui survit
//  au `flutter create` du build TV. Pas de mot de passe dedans.
// =========================================================

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zuno_mail/zuno_mail.dart';

import '../domain/audio_report_book.dart';
import '../domain/sound_report_mail.dart';

class SoundReportMailer {
  SoundReportMailer._();

  static const MethodChannel channel = MethodChannel(kZunoMailChannel);

  /// Version affichée dans l'objet. Vide si l'OS ne la donne pas.
  static Future<String> versionLabel() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String name = info.version.trim();
      final String build = info.buildNumber.trim();
      if (name.isEmpty) return 'inconnue';
      if (build.isEmpty) return name;
      return '$name+$build';
    } catch (_) {
      return 'inconnue';
    }
  }

  /// Prépare le texte et demande l'ouverture. Ne jette pas :
  /// une box sans application e-mail ne doit pas fermer Zuno.
  static Future<SoundReportMailOutcome> open({
    required String report,
    required String version,
    DateTime? date,
  }) async {
    if (report.trim().isEmpty) {
      return SoundReportMail.fromNative('empty');
    }
    final DateTime when = date ?? DateTime.now();
    try {
      SoundReportMail mail = SoundReportMail.compose(
        report: report,
        version: version,
        date: when,
      );
      String? path;
      if (mail.mode == SoundReportMailMode.attachment) {
        path = await _writeCache(mail.attachmentText ?? '');
        if (path == null) {
          mail = SoundReportMail.compose(
            report: report,
            version: version,
            date: when,
            allowAttachment: false,
          );
        }
      }
      String status = await _invoke(mail, path);
      if (status == 'too_large') {
        path ??= await _writeCache(redactAudioText(report));
        mail = SoundReportMail.shrink(
          report: report,
          version: version,
          date: when,
          allowAttachment: path != null,
        );
        status = await _invoke(mail, path);
      }
      return SoundReportMail.fromNative(status);
    } catch (_) {
      return SoundReportMail.fromNative('error');
    }
  }

  /// Copie durable, proposée quand l'e-mail n'a pas pu s'ouvrir.
  /// Le texte est nettoyé comme « Copier le rapport ».
  static Future<String?> saveToDocuments(String report) async {
    try {
      final String clean = redactAudioText(report);
      if (clean.trim().isEmpty) return null;
      final Directory dir = await getApplicationDocumentsDirectory();
      final Directory folder = Directory('${dir.path}/rapports-son');
      await folder.create(recursive: true);
      final DateTime now = DateTime.now();
      final String stamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final File file = File('${folder.path}/rapport-son-$stamp.txt');
      await file.writeAsString(clean, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Fichier lu par le FileProvider du plugin (cache/sound-report).
  static Future<String?> _writeCache(String text) async {
    if (text.isEmpty) return null;
    try {
      final Directory dir = await getTemporaryDirectory();
      final Directory folder = Directory('${dir.path}/sound-report');
      await folder.create(recursive: true);
      final File file = File('${folder.path}/rapport-son.txt');
      await file.writeAsString(text, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _invoke(SoundReportMail mail, String? filePath) async {
    if (!Platform.isAndroid) return 'no_app';
    try {
      final Object? raw = await channel.invokeMethod<Object>('open', <String, Object?>{
        'subject': mail.subject,
        'body': mail.body,
        'filePath': filePath,
      });
      if (raw is String && raw.isNotEmpty) return raw;
      return 'error';
    } catch (_) {
      return 'error';
    }
  }
}
