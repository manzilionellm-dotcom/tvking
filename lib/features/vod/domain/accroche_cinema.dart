// =========================================================
//  accroche_cinema.dart — ce qui donne envie de REVENIR au Cinéma
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (21/09/2026) : « côté cinéma, tu peux ajouter
//  des choses qui rendent accro ».
//
//  Ce que Netflix a mesuré, et que tout le monde a copié : ce qui fait
//  revenir, ce n'est pas la taille du catalogue, c'est trois rangées
//  qui créent un réflexe.
//
//    1. LE TOP 10 avec ses grands numéros. Le chiffre attire l'œil avant
//       l'affiche ; « numéro 1 » se regarde parce que c'est le numéro 1.
//       Netflix le calcule sur ses vues. Nous n'avons pas les vues de
//       tous les clients (et on n'invente rien) : on classe sur la NOTE
//       fournie par le catalogue, départagée par la fraîcheur d'ajout.
//       Le titre de la rangée le dit : « les mieux notés ».
//
//    2. LES SAGAS. « Vous avez vu le 1 ? Il y en a 8. » Une saga
//       complète, c'est huit soirées promises d'un coup — le binge des
//       films. Les fournisseurs livrent « Fast & Furious 7 », « Harry
//       Potter 3 », « Rocky II » en vrac dans les catégories ; on les
//       regroupe par titre de base et on ne montre que les sagas d'au
//       moins trois films.
//
//    3. LE COMPTEUR DE NOUVEAUTÉS sur la tuile Films de l'accueil
//       (« 12 nouveautés ») : la petite pastille qui fait entrer, comme
//       un badge d'app. Calculé par VodNoveltyService, affiché par
//       l'accueil — pas ici.
//
//  Fonctions PURES, sans Flutter : elles se testent sur de vrais noms de
//  catalogue (cf. accroche_cinema_test.dart).
// =========================================================
import 'vod_movie.dart';

/// Une saga : son titre de base et ses films, du premier au dernier.
class Saga {
  const Saga({required this.titre, required this.films});
  final String titre;
  final List<VodMovie> films;
}

/// Note numérique d'un film, ou `null` si le catalogue n'en donne pas
/// d'exploitable. « 7.4 », « 7,4 », « 7.4/10 » sont acceptés ; « 0 » et
/// « N/A » ne comptent pas (un zéro, chez Xtream, veut dire « inconnu »).
double? noteDe(VodMovie m) {
  final String brut = (m.rating ?? '').trim().replaceAll(',', '.');
  if (brut.isEmpty) return null;
  final RegExpMatch? x = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(brut);
  if (x == null) return null;
  final double v = double.parse(x.group(1)!);
  if (v <= 0 || v > 10) return null;
  return v;
}

/// Le TOP 10 : les mieux notés, départagés par la date d'ajout (le plus
/// récent devant). Moins de dix films notés → une liste plus courte ;
/// aucun → vide, et la rangée n'apparaît pas (on ne classe pas au hasard).
List<VodMovie> top10(List<VodMovie> films, {int taille = 10}) {
  final List<(VodMovie, double)> notes = <(VodMovie, double)>[
    for (final VodMovie m in films)
      if (noteDe(m) case final double n) (m, n),
  ];
  notes.sort(((VodMovie, double) a, (VodMovie, double) b) {
    final int c = b.$2.compareTo(a.$2);
    if (c != 0) return c;
    return (b.$1.addedEpoch ?? 0).compareTo(a.$1.addedEpoch ?? 0);
  });
  return <VodMovie>[for (final (VodMovie m, _) in notes.take(taille)) m];
}

/// Chiffres romains que les fournisseurs utilisent pour numéroter.
const Map<String, int> _romains = <String, int>{
  'i': 1, 'ii': 2, 'iii': 3, 'iv': 4, 'v': 5, 'vi': 6, 'vii': 7,
  'viii': 8, 'ix': 9, 'x': 10,
};

/// Le TITRE DE BASE et le NUMÉRO d'un film de saga, ou `null` si le nom
/// ne ressemble pas à un épisode numéroté.
///
/// Reconnu : « Rocky 2 », « Rocky II », « Rocky: Part 2 », « Rocky 2 -
/// La Revanche », « Rocky 2 (1979) », « Fast & Furious 7 », « Harry
/// Potter 3 ». Le numéro doit être PETIT (≤ 20) : « Blade Runner 2049 »
/// et « 2012 » ne sont pas des sagas, ni « Apollo 13 » (un seul film,
/// il tombera au filtre des trois minimum).
({String base, int numero})? episodeDeSaga(String nomBrut) {
  String t = nomBrut.trim();
  // On enlève ce qui suit le numéro : année entre parenthèses, sous-titre
  // après « - », « : » ou « – ».
  t = t.replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '');
  final RegExpMatch? m = RegExp(
    r'^(.+?)\s*(?:[:\-–]\s*)?(?:part(?:ie)?\s+|chapitre\s+|chapter\s+)?'
    r'(\d{1,2}|[ivx]{1,4})(?:\s*[:\-–].*)?$',
    caseSensitive: false,
  ).firstMatch(t);
  if (m == null) return null;
  final String base = m.group(1)!.trim().replaceAll(RegExp(r'[\s:\-–]+$'), '');
  if (base.length < 3) return null;
  final String num = m.group(2)!.toLowerCase();
  final int? n = int.tryParse(num) ?? _romains[num];
  if (n == null || n < 1 || n > 20) return null;
  return (base: base, numero: n);
}

/// Les SAGAS d'un catalogue : groupes d'au moins [minimum] films portant
/// le même titre de base (insensible à la casse), rangés par numéro. Le
/// premier film d'une saga (« Rocky », sans numéro) est rattaché s'il
/// existe sous ce nom exact. Ordre de sortie : la plus longue d'abord.
List<Saga> sagas(List<VodMovie> films, {int minimum = 3}) {
  // base normalisée → (numéro → film). Un numéro déjà pris ne s'écrase
  // pas : le premier venu reste (doublons HD/4K du fournisseur).
  final Map<String, Map<int, VodMovie>> groupes = <String, Map<int, VodMovie>>{};
  final Map<String, String> libelle = <String, String>{};
  for (final VodMovie m in films) {
    final ({String base, int numero})? e = episodeDeSaga(m.name);
    if (e == null) continue;
    final String cle = e.base.toLowerCase();
    libelle.putIfAbsent(cle, () => e.base);
    (groupes[cle] ??= <int, VodMovie>{}).putIfAbsent(e.numero, () => m);
  }
  // Le « numéro 1 » sans chiffre : « Rocky » pour la saga « Rocky ».
  for (final VodMovie m in films) {
    final String cle = m.name.trim().toLowerCase();
    final Map<int, VodMovie>? g = groupes[cle];
    if (g != null) g.putIfAbsent(1, () => m);
  }
  final List<Saga> out = <Saga>[
    for (final MapEntry<String, Map<int, VodMovie>> e in groupes.entries)
      if (e.value.length >= minimum)
        Saga(
          titre: libelle[e.key]!,
          films: <VodMovie>[
            for (final int n in e.value.keys.toList()..sort()) e.value[n]!,
          ],
        ),
  ];
  out.sort((Saga a, Saga b) => b.films.length.compareTo(a.films.length));
  return out;
}
