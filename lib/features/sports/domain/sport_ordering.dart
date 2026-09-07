// =========================================================
//  sport_ordering.dart — Les RÈGLES D'ORDRE du coin Sport (pur, testé)
// =========================================================
//  Demande du propriétaire (07/09/2026), mot pour mot :
//    • « Ordre des filtres : Football, Basket, Tennis, Baseball. Football
//      sélectionné par défaut, jamais en dernier. »
//    • « Les matchs EN DIRECT passent en premier … Les matchs à venir
//      suivent, triés par heure. »
//
//  Ces deux règles vivent ICI, en fonctions pures, et nulle part dans les
//  widgets : elles se testent sans écran, et un futur écran (TV) les
//  réutilisera telles quelles au lieu de les recopier.
// =========================================================
import 'sport_models.dart';

/// Noms de disciplines tels que la source les écrit. L'ordre est celui
/// voulu par le propriétaire ; tout le reste vient après, alphabétique.
const List<String> kPinnedSports = <String>[
  'Soccer',
  'Basketball',
  'Tennis',
  'Baseball',
];

/// Range les disciplines disponibles : les quatre épinglées d'abord, dans
/// leur ordre, puis les autres par ordre alphabétique. Une discipline
/// épinglée absente des affiches du moment n'apparaît pas (un filtre
/// « Tennis » sans tennis serait un mensonge).
List<String> orderSports(Iterable<String> available) {
  final Set<String> present = available.where((String s) => s.isNotEmpty).toSet();
  final List<String> out = <String>[];
  for (final String p in kPinnedSports) {
    final String? match = _findIgnoringCase(present, p);
    if (match != null) {
      out.add(match);
      present.remove(match);
    }
  }
  final List<String> rest = present.toList()
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return <String>[...out, ...rest];
}

String? _findIgnoringCase(Set<String> set, String wanted) {
  final String w = wanted.toLowerCase();
  for (final String s in set) {
    if (s.toLowerCase() == w) return s;
  }
  return null;
}

/// Filtre à sélectionner par défaut : le football s'il est là, sinon la
/// première discipline disponible, sinon rien (« Tous »).
String? defaultSport(List<String> ordered) {
  if (ordered.isEmpty) return null;
  return _findIgnoringCase(ordered.toSet(), 'Soccer') ?? ordered.first;
}

/// Ordonne une liste de matchs pour l'affichage :
///   1. ceux qui sont EN DIRECT (selon [isLive]), en tête, dans l'ordre où
///      la source les a classés (elle met les grandes affiches d'abord) ;
///   2. puis les autres, du plus proche coup d'envoi au plus lointain ;
///      les matchs sans horaire connu ferment la marche.
///
/// Un match déjà TERMINÉ (score connu, pas en direct) reste après les
/// matchs à venir : un résultat d'hier ne doit pas cacher le match de
/// ce soir.
List<SportEvent> orderMatches(
  List<SportEvent> events, {
  required bool Function(SportEvent) isLive,
  required DateTime now,
}) {
  final List<SportEvent> live = <SportEvent>[];
  final List<SportEvent> upcoming = <SportEvent>[];
  final List<SportEvent> finished = <SportEvent>[];
  final List<SportEvent> undated = <SportEvent>[];
  for (final SportEvent e in events) {
    if (isLive(e)) {
      live.add(e);
      continue;
    }
    final DateTime? k = e.startsAt;
    if (k == null) {
      undated.add(e);
    } else if (e.hasScore && k.isBefore(now)) {
      finished.add(e);
    } else {
      upcoming.add(e);
    }
  }
  int byKickoff(SportEvent a, SportEvent b) =>
      a.startsAt!.compareTo(b.startsAt!);
  upcoming.sort(byKickoff);
  // Les terminés : le plus récent d'abord (le résultat d'hier avant celui
  // de la semaine dernière).
  finished.sort((SportEvent a, SportEvent b) => byKickoff(b, a));
  return <SportEvent>[...live, ...upcoming, ...finished, ...undated];
}
