// =========================================================
//  sport_country_prefs.dart — LE PAYS DE DIFFUSION DU CLIENT
// =========================================================
//  Demande du propriétaire (07/09/2026) : « il faut que le client
//  choisisse son pays, et il va voir si son pays va montrer ses matchs.
//  Genre les apps haut niveau. »
//
//  CE QUE FONT LES GRANDES APPS, ET CE QU'ON FAIT DE MIEUX. SofaScore ou
//  FotMob tiennent un annuaire mondial « ce match passe sur telle chaîne
//  dans tel pays ». C'est un travail éditorial permanent, et surtout ça
//  reste théorique : ils annoncent une chaîne que le client n'a
//  peut-être pas.
//
//  Nous, on a mieux — la playlist RÉELLE du client. On ne lui annonce
//  jamais une chaîne qu'il ne possède pas. Le pays sert donc à TRANCHER
//  entre plusieurs chaînes qui diffusent le même match : un Suédois veut
//  son commentaire suédois, pas le flux arabe qui passe le même match.
//
//  ---------------------------------------------------------
//  ON NE PROPOSE QUE CE QU'IL A
//  ---------------------------------------------------------
//  La liste des pays n'est PAS une liste du monde codée en dur : elle
//  est déduite des chaînes réellement présentes chez lui, et classée par
//  nombre de chaînes. Un client qui n'a que du français et de l'arabe
//  voit deux entrées, pas cent quatre-vingt-quinze. C'est ça, la
//  différence entre un formulaire et un produit.
//
//  Vide (`''`) = « tous les pays », et c'est le défaut : tant que le
//  client n'a rien choisi, on ne préfère rien et on ne cache rien.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';

/// Un pays présent dans la playlist du client, avec son poids.
@immutable
class SportCountryOption {
  const SportCountryOption(this.info, this.channelCount);
  final CountryInfo info;

  /// Nombre de chaînes de ce pays chez le client. Sert à classer : le
  /// pays le plus fourni est presque toujours le sien.
  final int channelCount;
}

class SportCountryPrefs extends ChangeNotifier {
  SportCountryPrefs._();
  static final SportCountryPrefs instance = SportCountryPrefs._();

  static const String _kKey = 'sports.broadcast_country.v1';

  String _code = '';
  bool _loaded = false;

  /// Code ISO du pays choisi, ou '' pour « tous les pays ».
  String get code => _code;
  bool get hasChoice => _code.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _code = p.getString(_kKey) ?? '';
      notifyListeners();
    } catch (_) {
      // Préférences illisibles : on reste sur « tous les pays ». Ce
      // réglage est un confort, il ne doit jamais empêcher l'écran de
      // s'afficher.
    }
  }

  Future<void> setCode(String code) async {
    if (_code == code) return;
    _code = code;
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      if (code.isEmpty) {
        await p.remove(_kKey);
      } else {
        await p.setString(_kKey, code);
      }
    } catch (_) {
      // Le choix vaut pour cette session même si l'écriture échoue.
    }
  }

  @visibleForTesting
  void debugSet(String code) {
    _code = code;
    _loaded = true;
  }

  /// Les pays réellement présents dans [channels], du plus fourni au
  /// moins fourni. Fonction PURE : testable sans playlist ni base.
  ///
  /// À égalité de nombre de chaînes, on classe par nom pour que l'ordre
  /// ne danse pas d'une ouverture à l'autre — un menu qui change d'ordre
  /// tout seul est un menu qu'on n'apprend jamais.
  static List<SportCountryOption> optionsFrom(List<Channel> channels) {
    final Map<String, int> counts = <String, int>{};
    final Map<String, CountryInfo> infos = <String, CountryInfo>{};
    for (final Channel c in channels) {
      final CountryInfo? info = c.country;
      if (info == null) continue;
      counts[info.code] = (counts[info.code] ?? 0) + 1;
      infos[info.code] = info;
    }
    final List<SportCountryOption> out = <SportCountryOption>[
      for (final MapEntry<String, int> e in counts.entries)
        SportCountryOption(infos[e.key]!, e.value),
    ];
    out.sort((SportCountryOption a, SportCountryOption b) {
      final int parNombre = b.channelCount.compareTo(a.channelCount);
      if (parNombre != 0) return parNombre;
      return a.info.name.compareTo(b.info.name);
    });
    return out;
  }
}
