// =========================================================
//  genre_l10n.dart — Libellés traduits des genres et pays
// =========================================================
//  Le domain (`channel_genre.dart`) reste PUR : il classifie les
//  chaînes et porte des libellés français de repli, sans dépendre
//  de Flutter l10n. Mais tout ce que l'UTILISATEUR voit doit suivre
//  la langue du téléphone (8 langues supportées).
//
//  Ces extensions font le pont côté presentation :
//    channel.genre.localizedLabel(context.l10n)
//    channel.country!.localizedLabel(context.l10n)
//
//  On RÉUTILISE les clés existantes quand la valeur française
//  correspond déjà (sectionMovies = « Films », catInfo = « Info »…)
//  pour ne pas dupliquer les traductions.
// =========================================================

import '../../../l10n/generated/app_localizations.dart';
import '../domain/channel_genre.dart';

/// Libellé traduit d'un [ChannelGenre] (affichage uniquement —
/// la classification continue d'utiliser les mots-clés du domain).
extension ChannelGenreL10n on ChannelGenre {
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case ChannelGenre.sports:
        return l10n.genreSports;
      case ChannelGenre.movies:
        return l10n.sectionMovies;
      case ChannelGenre.series:
        return l10n.sectionSeries;
      case ChannelGenre.kids:
        return l10n.sectionKids;
      case ChannelGenre.news:
        return l10n.catInfo;
      case ChannelGenre.music:
        return l10n.sectionMusic;
      case ChannelGenre.documentary:
        return l10n.genreDocumentary;
      case ChannelGenre.entertainment:
        return l10n.sectionEntertainment;
      case ChannelGenre.international:
        return l10n.sectionInternational;
      case ChannelGenre.adult:
        return l10n.sectionAdult;
      case ChannelGenre.other:
        return l10n.sectionOthers;
    }
  }
}

/// Nom de pays traduit d'un [CountryInfo]. Le switch porte sur le
/// `code` ISO (stable) — si un pays inconnu apparaît un jour dans le
/// domain sans clé ici, on retombe sur son nom français (`name`),
/// jamais sur un écran vide.
extension CountryInfoL10n on CountryInfo {
  String localizedLabel(AppLocalizations l10n) {
    switch (code) {
      case 'FR':
        return l10n.countryFrance;
      case 'US':
        return l10n.countryUnitedStates;
      case 'UK':
        return l10n.countryUnitedKingdom;
      case 'DE':
        return l10n.countryGermany;
      case 'IT':
        return l10n.countryItaly;
      case 'ES':
        return l10n.countrySpain;
      case 'PT':
        return l10n.countryPortugal;
      case 'BE':
        return l10n.countryBelgium;
      case 'CH':
        return l10n.countrySwitzerland;
      case 'CA':
        return l10n.countryCanada;
      case 'BR':
        return l10n.countryBrazil;
      case 'MX':
        return l10n.countryMexico;
      case 'AR':
        return l10n.countryArgentina;
      case 'SA':
        return l10n.countrySaudiArabia;
      case 'TR':
        return l10n.countryTurkey;
      case 'GR':
        return l10n.countryGreece;
      case 'PL':
        return l10n.countryPoland;
      case 'RU':
        return l10n.countryRussia;
      case 'NL':
        return l10n.countryNetherlands;
      case 'JP':
        return l10n.countryJapan;
      case 'KR':
        return l10n.countryKorea;
      case 'CN':
        return l10n.countryChina;
      case 'IN':
        return l10n.countryIndia;
      case 'AU':
        return l10n.countryAustralia;
      case 'SE':
        return l10n.countrySweden;
      case 'NO':
        return l10n.countryNorway;
      case 'DK':
        return l10n.countryDenmark;
      case 'FI':
        return l10n.countryFinland;
      case 'MA':
        return l10n.countryMorocco;
      case 'DZ':
        return l10n.countryAlgeria;
      case 'TN':
        return l10n.countryTunisia;
      case 'EG':
        return l10n.countryEgypt;
      default:
        return name; // Repli : libellé français du domain.
    }
  }
}
