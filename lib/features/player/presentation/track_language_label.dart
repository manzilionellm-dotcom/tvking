// =========================================================
//  track_language_label.dart — Libellé LOCALISÉ d'un code langue
// =========================================================
//  Les pistes audio/sous-titres remontent des codes ISO bruts
//  (fr, eng, spa…). Ce helper les traduit en libellés humains via
//  AppLocalizations. Il ne dépend QUE de widgets + l10n : il est
//  donc importable par le LECTEUR TV (build TV sans media_kit)
//  comme par le lecteur mobile. Code inconnu → majuscules (repli
//  technique, comme la feuille mobile).
// =========================================================

import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';

/// Nom localisé de la langue [code] (ISO 639-1/2), ex. « Français ».
String trackLanguageLabel(BuildContext context, String code) {
  switch (code.toLowerCase()) {
    case 'fr':
    case 'fre':
    case 'fra':
      return context.l10n.trackLangFrench;
    case 'en':
    case 'eng':
      return context.l10n.trackLangEnglish;
    case 'es':
    case 'spa':
      return context.l10n.trackLangSpanish;
    case 'de':
    case 'ger':
    case 'deu':
      return context.l10n.trackLangGerman;
    case 'it':
    case 'ita':
      return context.l10n.trackLangItalian;
    case 'ar':
    case 'ara':
      return context.l10n.trackLangArabic;
    case 'pt':
    case 'por':
      return context.l10n.trackLangPortuguese;
    case 'ru':
    case 'rus':
      return context.l10n.trackLangRussian;
    case 'zh':
    case 'chi':
      return context.l10n.trackLangChinese;
    case 'ja':
    case 'jpn':
      return context.l10n.trackLangJapanese;
    case 'ko':
    case 'kor':
      return context.l10n.trackLangKorean;
    default:
      return code.toUpperCase();
  }
}
