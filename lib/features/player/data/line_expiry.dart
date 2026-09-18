// =========================================================
//  line_expiry.dart — « la ligne du fournisseur est-elle morte ? »
// =========================================================
//  POURQUOI CE FICHIER EXISTE (12/09/2026).
//
//  Photo du propriétaire : on est le 12/09/2026, et l'app annonce
//  « Your subscription expired on 13/09/2026 ». Une date qui n'est PAS
//  encore arrivée. Son mot : « il termine le m3u avant sa date ».
//
//  Ce n'est pas un défaut d'affichage. Le verdict « expiré » ne fait pas
//  qu'écrire une phrase : il ARRÊTE DÉFINITIVEMENT les reconnexions du
//  relais (local_stream_relay._abortIfLineDead). Un verdict trop hâtif ne
//  se contente donc pas de mentir au client — il lui coupe la télévision
//  alors qu'il a payé, et aucune relance ne la rallumera.
//
//  Trois défauts se cumulaient, chacun suffisant à lui seul :
//
//  1. LE MESSAGE NOMMAIT LE MAUVAIS JOUR. Chez Xtream, `exp_date` est
//     l'instant de FIN, pas le dernier jour couvert. Un panel qui écrit
//     « 13/09 00:00 » dit « valable jusqu'à la fin du 12 ». L'app
//     recopiait l'instant tel quel : « expiré le 13/09 » — un jour que
//     le client n'a jamais eu, annoncé la veille. D'où sa phrase.
//
//  2. ON COMPARAIT À L'HORLOGE DE L'APPAREIL. La date de fin est posée
//     par le PANEL, dans le fuseau du PANEL. On la comparait à l'heure
//     du téléphone. Une box dont l'horloge avance (réglage manuel,
//     absence de NTP, fuseau faux — banal sur les boîtiers bon marché)
//     déclare la ligne morte avant l'heure, pour de bon. Le panel envoie
//     pourtant sa propre heure dans `server_info.timestamp_now` : c'est
//     ELLE qui fait autorité sur la vie d'une ligne, pas notre montre.
//
//  3. AUCUNE MARGE, ET UN STATUT QUI PRIME SUR LA DATE. La coupure se
//     jouait à la seconde près, et un statut contenant « expired »
//     suffisait à tuer la ligne même quand la date de fin était encore
//     loin devant. Or ces deux informations viennent du même panel : si
//     elles se contredisent, c'est le panel qui se trompe, pas le
//     client. Accuser dans le doute, c'est facturer un appel au support.
//
//  RÈGLE RETENUE, et elle est asymétrique À DESSEIN : se tromper en
//  disant « vivante » coûte un écran noir de plus, que le client
//  comprend (il appelle son fournisseur). Se tromper en disant
//  « morte » coupe la télé d'un client qui a payé ET verrouille les
//  reconnexions. Les deux erreurs ne pèsent pas le même poids : dans le
//  doute, la ligne est VIVANTE.
//
//  UNE SEULE IMPLÉMENTATION, AUTANT D'APPELANTS QU'ON VEUT (règle de la
//  maison, cf. cloudflare/device_profiles.js). Quatre endroits jugeaient
//  l'expiration chacun dans son coin — la boîte noire, le lecteur
//  téléphone, le lecteur TV, la calibration de source. Ils avaient déjà
//  divergé une fois : la boîte noire disait « expiré » pendant que
//  l'écran, lui, avait un garde-fou. Ici, tout le monde appelle
//  [jugerLigne], et le jour où la règle change, elle change une fois.
//
//  Ce fichier est du Dart PUR (aucun import Flutter) : il se teste sans
//  émulateur, sans écran, sans réseau — voir
//  test/features/player/line_expiry_test.dart.
// =========================================================

/// Ce que l'on sait de la vie d'une ligne fournisseur.
enum VerdictLigne {
  /// Rien n'accuse la ligne : on lit, on reconnecte, on n'affiche aucune
  /// accusation. C'est le repli quand on ne sait pas.
  vivante,

  /// La ligne est bel et bien terminée : date de fin dépassée (marge
  /// comprise), ou statut de fin sans date qui le contredise.
  morte,

  /// Le panel se contredit : il dit « expired » alors que la date de fin
  /// qu'il donne lui-même est encore devant nous.
  ///
  /// On ne coupe PAS et on n'accuse PAS l'abonnement. Le client reçoit un
  /// message factuel (« le flux ne répond pas chez ton fournisseur »), et
  /// le cas part dans la boîte noire pour le support — c'est là que le
  /// revendeur verra que le panel raconte n'importe quoi.
  contradictoire,
}

/// Marge avant de déclarer une ligne morte SUR LA DATE.
///
/// Pourquoi douze heures, et pas zéro : la date de fin est posée par le
/// panel, dans son fuseau, souvent à minuit. On la compare — au mieux — à
/// l'horloge de ce même panel, et — au pire, quand il ne la donne pas —
/// à celle de l'appareil. Entre un panel à Londres, une box réglée à la
/// main et un client à Stockholm, un écart de quelques heures est la
/// normale, pas l'exception.
///
/// Ce que cette marge coûte : un client réellement expiré peut lire une
/// demi-journée de plus. Ce qu'elle évite : couper un client qui a payé.
/// Le fournisseur, lui, coupe de son côté quand il veut — sa décision ne
/// dépend pas de nous. La marge ne donne donc rien gratuitement : elle
/// nous empêche seulement de couper AVANT lui.
const Duration kMargeExpiration = Duration(hours: 12);

/// Statuts de panel qui signifient « ligne terminée ».
///
/// On compare en minuscules et sur le mot ENTIER (`==`), pas en
/// `contains` : un panel qui répondrait « Not Expired » ou
/// « expired_soon » ne doit pas être lu à l'envers. C'est exactement le
/// genre de piège que le protocole Xtream, non normalisé, tend.
const Set<String> _statutsDeFin = <String>{'expired', 'expire', 'ended'};

/// Statuts qui signifient « compte puni » (banni/suspendu/désactivé).
/// Rangés ici pour que TOUTE la lecture du champ `status` vive au même
/// endroit — sinon elle se dédouble, et une liste finit par oublier un mot.
///
/// CETTE LISTE NE S'ÉLARGIT PAS À LA LÉGÈRE. Elle est reprise TELLE QUELLE
/// du lecteur, et volontairement plus courte que celle qu'utilisait la
/// calibration de source (qui ajoutait « blocked » et « inactive »). La
/// raison est la même que pour toute cette page : « banni » arrête, lui
/// aussi, les reconnexions du relais. Ajouter un mot ici, c'est créer une
/// nouvelle façon de couper la télévision d'un client — en unifiant deux
/// listes, on prend donc la PLUS PRUDENTE, jamais l'union des deux.
const Set<String> _statutsDeSanction = <String>{
  'banned', 'disabled', 'suspend',
};

/// Le panel dit-il que le compte est sanctionné (banni/suspendu) ?
/// Ici on reste en `contains` : c'est une accusation que le panel porte
/// explicitement, et les formulations varient (« Banned », « user disabled »).
bool statutSanctionne(String? statut) {
  final String s = (statut ?? '').trim().toLowerCase();
  if (s.isEmpty) return false;
  return _statutsDeSanction.any(s.contains);
}

/// Le panel dit-il que la ligne est terminée ?
bool statutDeFin(String? statut) =>
    _statutsDeFin.contains((statut ?? '').trim().toLowerCase());

/// Verdict complet sur une ligne.
///
/// [statut] : le champ `status` du panel (`Active`, `Expired`…), tel quel.
/// [finDeLigne] : `exp_date` converti en DateTime. `null` = illimité ou
///   non communiqué — et « non communiqué » ne vaut jamais « expiré ».
/// [horlogeAppareil] : `DateTime.now()`, passé explicitement pour que ce
///   fichier reste pur et testable.
/// [horlogePanel] : `server_info.timestamp_now` converti, si le panel l'a
///   donné. C'est LUI qui fait autorité : la date de fin vient du panel,
///   elle se juge à l'heure du panel.
/// [marge] : voir [kMargeExpiration].
VerdictLigne jugerLigne({
  required String? statut,
  required DateTime? finDeLigne,
  required DateTime horlogeAppareil,
  DateTime? horlogePanel,
  Duration marge = kMargeExpiration,
}) {
  final DateTime maintenant = horlogePanel ?? horlogeAppareil;
  final bool leStatutDitFin = statutDeFin(statut);

  if (finDeLigne == null) {
    // Pas de date : le statut est le seul indice. Un panel qui dit
    // « Expired » sans donner de date reste crédible — il n'y a rien pour
    // le contredire.
    return leStatutDitFin ? VerdictLigne.morte : VerdictLigne.vivante;
  }

  // La date est-elle dépassée, marge comprise ?
  final bool dateDepassee = maintenant.isAfter(finDeLigne.add(marge));
  if (dateDepassee) return VerdictLigne.morte;

  // La date tient encore. Si le statut crie quand même « expired », les
  // deux affirmations du MÊME panel se contredisent : on ne coupe pas.
  if (leStatutDitFin) return VerdictLigne.contradictoire;

  return VerdictLigne.vivante;
}

/// Le DERNIER JOUR RÉELLEMENT COUVERT par la ligne — celui qu'il faut
/// écrire au client, et pas l'instant de fin brut.
///
/// `exp_date` marque la FIN. Un panel qui pose « 13/09 00:00:00 » couvre
/// jusqu'à la dernière seconde du 12 : annoncer « expiré le 13 » nomme un
/// jour que le client n'a jamais eu — et, quand on est le 12, annonce une
/// date qui n'est même pas arrivée.
///
/// Reculer d'une seconde règle les deux cas d'un coup, sans rien casser :
/// une fin à minuit pile retombe sur la veille (le bon jour), une fin en
/// milieu de journée (13/09 14:30) reste sur son propre jour (13/09), qui
/// est bien le dernier couvert.
DateTime dernierJourCouvert(DateTime finDeLigne) =>
    finDeLigne.subtract(const Duration(seconds: 1));

/// Formate un jour en `JJ/MM/AAAA` — la forme que le propriétaire lit au
/// téléphone avec ses clients. Ici et nulle part ailleurs : le même jour
/// s'écrivait de deux façons selon l'écran (avec et sans zéro devant).
String formatJour(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Lit l'heure du panel depuis le bloc `server_info` de player_api.php.
///
/// On n'accepte QUE `timestamp_now` (epoch secondes) : c'est le seul champ
/// non ambigu. Son voisin `time_now` est une chaîne « 2026-09-12 15:15:01 »
/// exprimée dans le fuseau du panel, sans décalage écrit — la lire
/// reviendrait à deviner, et deviner l'heure est précisément le défaut
/// qu'on corrige ici.
///
/// Garde-fou : une valeur absurde (avant 2020, ou à plus d'un an devant)
/// est REJETÉE. Un panel qui renvoie 0, ou une date de 1970, ferait
/// paraître toutes les lignes éternelles ; un panel réglé en 2099 les
/// tuerait toutes d'un coup. Dans les deux cas on retombe simplement sur
/// l'horloge de l'appareil, qui est le comportement d'avant.
DateTime? horlogePanelDepuisServerInfo(Map<String, dynamic>? serverInfo) {
  if (serverInfo == null) return null;
  final Object? brut = serverInfo['timestamp_now'];
  if (brut == null) return null;
  final int? secondes =
      brut is int ? brut : int.tryParse(brut.toString().trim());
  if (secondes == null || secondes <= 0) return null;
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(secondes * 1000);
  if (t.year < 2020 || t.year > DateTime.now().year + 1) return null;
  return t;
}
