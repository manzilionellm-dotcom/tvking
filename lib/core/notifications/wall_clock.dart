// =========================================================
//  wall_clock.dart — Heures « murales » LOCALES pour les rappels
// =========================================================
//  BUG CORRIGÉ : les nudges « 20 h » / « 19 h » étaient construits avec
//  tz.TZDateTime(tz.local, …) alors que tz.setLocalLocation() n'est
//  JAMAIS appelé → tz.local == UTC. Résultat : le rappel « ce soir à
//  20 h » sonnait à 20 h UTC (22 h en France l'été, 21 h l'hiver).
//
//  Ici on calcule l'heure murale avec l'horloge LOCALE de l'appareil
//  (DateTime.now(), toujours juste — la box connaît son fuseau), puis le
//  service convertit cet INSTANT ABSOLU en TZDateTime UTC pour le plugin
//  (même technique que les rappels de programme EPG, qui eux étaient
//  déjà corrects). Fonctions PURES → testées sans plugin ni fuseau.
// =========================================================

/// Prochaine occurrence locale de `hour` h pile : aujourd'hui si elle est
/// encore à venir, sinon demain. Le passage par le CONSTRUCTEUR (jour + 1
/// normalisé par DateTime) — et non par add(Duration(days: 1)) — garde
/// l'heure murale exacte même à cheval sur un changement d'heure (DST).
DateTime nextLocalOccurrence(DateTime now, int hour) {
  final DateTime today = DateTime(now.year, now.month, now.day, hour);
  if (today.isAfter(now)) return today;
  return DateTime(now.year, now.month, now.day + 1, hour);
}

/// Jour J+[daysFromNow] à `hour` h locale (ex. « la veille de l'expiration,
/// à 19 h »). Même normalisation par le constructeur (DST-sûr).
DateTime localDayAt(DateTime now, int daysFromNow, int hour) {
  return DateTime(now.year, now.month, now.day + daysFromNow, hour);
}
