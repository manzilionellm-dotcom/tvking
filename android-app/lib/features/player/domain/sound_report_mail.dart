// =========================================================
//  sound_report_mail.dart — Préparer le courrier, sans l'envoyer
// =========================================================
//  Le bouton « Envoyer par e-mail » ne parle à aucun serveur.
//  Il n'y a pas de mot de passe, pas de jeton, pas de clé de
//  courrier ici. Ce fichier décide seulement :
//    • à qui (une adresse fixe, écrite en clair) ;
//    • l'objet (titre + version + date) ;
//    • le corps, le MÊME texte que « Copier le rapport »,
//      repassé dans le filet qui retire une adresse de flux
//      et un secret ;
//    • si le texte est trop long pour un intent Android, on
//      garde le début complet (coupé à une fin de ligne) et
//      le reste part dans un fichier .txt.
//
//  Ouvrir l'application e-mail, c'est le rôle de
//  sound_report_mailer.dart + du plugin zuno_mail. Ici, aucun
//  Android : les tests tournent sur la machine de build.
// =========================================================

import 'dart:convert';

import 'audio_report_book.dart';

/// Corps dans l'intent, ou corps court + fichier.
enum SoundReportMailMode { body, attachment }

/// Ce que le natif a répondu. L'ouverture réelle de l'application
/// e-mail ne se voit que sur un appareil.
enum SoundReportMailStatus { opened, noApp, error, empty }

class SoundReportMailOutcome {
  const SoundReportMailOutcome({required this.status, required this.message});

  final SoundReportMailStatus status;
  final String message;
}

/// Le courrier prêt à être confié à Android. [attachmentText] est
/// null quand tout tient dans [body].
class SoundReportMail {
  const SoundReportMail({
    required this.to,
    required this.subject,
    required this.body,
    required this.attachmentText,
    required this.mode,
  });

  /// Destinataire demandé. La même chaîne est recopiée dans le
  /// plugin Kotlin : un appel au canal ne peut pas la changer.
  static const String recipient = 'manzilionel.lm@gmail.com';

  /// Titre fixe. La version et la date sont ajoutées après.
  static const String subjectPrefix = 'Rapport son Zuno';

  /// Au-dessus, on ne met plus le rapport entier dans l'intent.
  /// Le tampon Binder d'Android est d'environ 1 Mo pour TOUTE la
  /// transaction : 100 Ko laisse de la marge. Le rapport complet
  /// est déjà plafonné à 12 000 caractères, donc le cas courant
  /// reste le corps, pas le fichier.
  static const int intentBodyMaxBytes = 100 * 1024;

  /// Début gardé dans le corps quand le fichier joint porte la suite.
  static const int previewMaxBytes = 4 * 1024;

  static const String attachedNote =
      '\n\nLe rapport complet est dans le fichier joint.';

  static const String truncatedNote =
      '\n\nTexte coupé : le début est complet, la suite n\'a pas tenu dans l\'e-mail.';

  static const String emptyMessage =
      'Faites d\'abord « Rapport son complet ».';

  static const String openedMessage =
      'L\'application e-mail est ouverte, destinataire déjà rempli. '
      'Il reste à appuyer sur Envoyer.';

  static const String noAppMessage =
      'Aucune application e-mail sur cet appareil. '
      'Le rapport est dans le presse-papiers. '
      'Vous pouvez aussi l\'enregistrer dans un fichier.';

  static const String errorMessage =
      'L\'e-mail n\'a pas pu s\'ouvrir. '
      'Le rapport est dans le presse-papiers. '
      'Vous pouvez aussi l\'enregistrer dans un fichier.';

  static const String savedPrefix = 'Fichier enregistré : ';

  static const String saveFailedMessage =
      'Le fichier n\'a pas pu être enregistré. '
      'Le rapport reste dans le presse-papiers.';

  final String to;
  final String subject;
  final String body;

  /// Texte intégral nettoyé, à écrire dans le .txt. Null si [body]
  /// contient déjà tout.
  final String? attachmentText;
  final SoundReportMailMode mode;

  /// [report] est le texte de « Copier le rapport ». On le nettoie
  /// encore une fois : le filet est idempotent.
  static SoundReportMail compose({
    required String report,
    required String version,
    required DateTime date,
    int maxBodyBytes = intentBodyMaxBytes,
    int previewMaxBytes = SoundReportMail.previewMaxBytes,
    bool allowAttachment = true,
  }) {
    final String clean = redactAudioText(report);
    final String subject = subjectLine(version, date);
    final int size = utf8.encode(clean).length;
    if (size <= maxBodyBytes) {
      return SoundReportMail(
        to: recipient,
        subject: subject,
        body: clean,
        attachmentText: null,
        mode: SoundReportMailMode.body,
      );
    }
    if (allowAttachment) {
      final String head = _head(clean, previewMaxBytes, attachedNote);
      return SoundReportMail(
        to: recipient,
        subject: subject,
        body: head,
        attachmentText: clean,
        mode: SoundReportMailMode.attachment,
      );
    }
    return SoundReportMail(
      to: recipient,
      subject: subject,
      body: _head(clean, maxBodyBytes, truncatedNote),
      attachmentText: null,
      mode: SoundReportMailMode.body,
    );
  }

  /// Deuxième essai, après un intent refusé pour taille.
  /// Le corps devient un début court. Le fichier, s'il est permis,
  /// garde le texte entier.
  static SoundReportMail shrink({
    required String report,
    required String version,
    required DateTime date,
    required bool allowAttachment,
  }) {
    return compose(
      report: report,
      version: version,
      date: date,
      maxBodyBytes: 2048,
      previewMaxBytes: 2048,
      allowAttachment: allowAttachment,
    );
  }

  static String subjectLine(String version, DateTime date) {
    final String raw = version.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    final String v = raw.isEmpty ? 'inconnue' : raw;
    final String y = date.year.toString().padLeft(4, '0');
    final String m = date.month.toString().padLeft(2, '0');
    final String d = date.day.toString().padLeft(2, '0');
    return '$subjectPrefix $v $y-$m-$d';
  }

  /// Traduit le mot renvoyé par le plugin. `too_large` n'arrive ici
  /// qu'après le second essai : on le traite comme un échec, le
  /// presse-papiers prend le relais.
  static SoundReportMailOutcome fromNative(String? status) {
    switch (status) {
      case 'opened':
        return const SoundReportMailOutcome(
          status: SoundReportMailStatus.opened,
          message: openedMessage,
        );
      case 'no_app':
        return const SoundReportMailOutcome(
          status: SoundReportMailStatus.noApp,
          message: noAppMessage,
        );
      case 'empty':
        return const SoundReportMailOutcome(
          status: SoundReportMailStatus.empty,
          message: emptyMessage,
        );
      default:
        return const SoundReportMailOutcome(
          status: SoundReportMailStatus.error,
          message: errorMessage,
        );
    }
  }

  /// Début du texte, au plus [maxBytes] octets UTF-8, note comprise.
  /// On coupe à une fin de ligne pour ne pas trancher une phrase.
  /// S'il n'y a aucune fin de ligne dans le budget, on coupe quand
  /// même sur une frontière de caractère : le début reste lisible.
  static String fitStart(String text, int maxBytes) {
    if (maxBytes <= 0 || text.isEmpty) return '';
    if (utf8.encode(text).length <= maxBytes) return text;
    var lo = 0;
    var hi = text.length;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (utf8.encode(text.substring(0, mid)).length <= maxBytes) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo <= 0) return '';
    final String cut = text.substring(0, lo);
    final int nl = cut.lastIndexOf('\n');
    if (nl > 0) return cut.substring(0, nl);
    return cut;
  }

  static String _head(String clean, int maxBytes, String note) {
    final int noteBytes = utf8.encode(note).length;
    if (noteBytes >= maxBytes) return fitStart(clean, maxBytes);
    final String head = fitStart(clean, maxBytes - noteBytes);
    if (head.isEmpty) return fitStart(clean, maxBytes);
    final String withNote = '$head$note';
    if (utf8.encode(withNote).length <= maxBytes) return withNote;
    return head;
  }
}
