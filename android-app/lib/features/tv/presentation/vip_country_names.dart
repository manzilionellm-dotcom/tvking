import '../../../l10n/generated/app_localizations.dart';

/// Libellés pays du sélecteur et du Direct dans la langue active.
/// Données régionales CLDR/ICU, matérialisées dans tous les catalogues ARB.
String vipCountryName(AppLocalizations l, String code) {
  switch (code.toLowerCase()) {
    case 'rs':
      return l.vipCountryRs;
    case 'fr':
      return l.vipCountryFr;
    case 'us':
      return l.vipCountryUs;
    case 'uk':
      return l.vipCountryUk;
    case 'de':
      return l.vipCountryDe;
    case 'it':
      return l.vipCountryIt;
    case 'es':
      return l.vipCountryEs;
    case 'pt':
      return l.vipCountryPt;
    case 'be':
      return l.vipCountryBe;
    case 'ch':
      return l.vipCountryCh;
    case 'ca':
      return l.vipCountryCa;
    case 'br':
      return l.vipCountryBr;
    case 'mx':
      return l.vipCountryMx;
    case 'ar':
      return l.vipCountryAr;
    case 'sa':
      return l.vipCountrySa;
    case 'tr':
      return l.vipCountryTr;
    case 'gr':
      return l.vipCountryGr;
    case 'pl':
      return l.vipCountryPl;
    case 'ru':
      return l.vipCountryRu;
    case 'nl':
      return l.vipCountryNl;
    case 'jp':
      return l.vipCountryJp;
    case 'kr':
      return l.vipCountryKr;
    case 'cn':
      return l.vipCountryCn;
    case 'in':
      return l.vipCountryIn;
    case 'au':
      return l.vipCountryAu;
    case 'se':
      return l.vipCountrySe;
    case 'no':
      return l.vipCountryNo;
    case 'dk':
      return l.vipCountryDk;
    case 'fi':
      return l.vipCountryFi;
    case 'ma':
      return l.vipCountryMa;
    case 'dz':
      return l.vipCountryDz;
    case 'tn':
      return l.vipCountryTn;
    case 'eg':
      return l.vipCountryEg;
    default:
      return code.toUpperCase();
  }
}
