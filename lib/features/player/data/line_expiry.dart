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
//  CORRECTIF DU 16/09/2026 (le client a ENCORE UN JOUR) :
//  le revendeur écrit « expire le 13/09 ». Chez Xtream, `exp_date` à
//  minuit le 13 est la DATE imprimée, pas « mort dès la première
//  seconde du 13 ». Le 13 est le DERNIER JOUR PAYÉ, entier. Couper le
//  12, ou le 13 au matin, c'est voler une journée. On juge donc :
//    — dernier jour couvert = le jour calendaire de `exp_date` ;
//    — mort seulement après le LENDEMAIN 00:00 + marge.
//
//  RÈGLE RETENUE, asymétrique À DESSEIN : se tromper en disant
//  « vivante » coûte un écran noir, que le client comprend. Se tromper
//  en disant « morte » coupe la télé d'un client qui a payé. Dans le
//  doute, la ligne est VIVANTE.
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

/// Marge après la fin du dernier jour calendaire.
///
/// Douze heures : fuseau panel vs box, minuit mal posé, NTP absent.
/// Un client vraiment fini peut lire une demi-journée de plus. Le
/// fournisseur coupe de son côté — on ne coupe jamais AVANT lui.
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

/// Premier instant NON couvert : lendemain 00:00 du jour calendaire
/// de [finDeLigne], puis + [marge].
DateTime _mortApres(DateTime finDeLigne, Duration marge) {
  final DateTime lendemain = DateTime(
    finDeLigne.year,
    finDeLigne.month,
    finDeLigne.day,
  ).add(const Duration(days: 1));
  return lendemain.add(marge);
}

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

  // Dernier jour calendaire INCLUS + marge. Un `exp_date` au 13/09 00:00
  // (ou 13/09 14:30) couvre TOUT le 13. Mort à partir du 14 00:00 + marge.
  final bool dateDepassee = maintenant.isAfter(_mortApres(finDeLigne, marge));
  if (dateDepassee) return VerdictLigne.morte;

  // La date tient encore. Si le statut crie quand même « expired », les
  // deux affirmations du MÊME panel se contredisent : on ne coupe pas.
  if (leStatutDitFin) return VerdictLigne.contradictoire;

  return VerdictLigne.vivante;
}

/// Le DERNIER JOUR RÉELLEMENT COUVERT — le jour que le panel imprime.
///
/// 16/09/2026 : « expire le 13/09 » = le 13 est payé en entier. Annoncer
/// la veille volait un jour au client (et affichait « terminé » trop tôt).
DateTime dernierJourCouvert(DateTime finDeLigne) =>
    DateTime(finDeLigne.year, finDeLigne.month, finDeLigne.day);

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
