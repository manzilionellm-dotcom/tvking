// =========================================================
//  tv_search_text.dart — Texte comparé par la recherche TV
// =========================================================
//  Le clavier à l'écran n'a que A–Z et 0–9 : pas d'accent, pas
//  d'apostrophe. « tele » doit quand même trouver « Téléfoot »,
//  et « lequipe » doit trouver « L'Équipe ».
//
//  On compare le NOM BRUT et la catégorie (chaînes peu coûteuses),
//  pas le nom « curé » : celui-ci relance des dizaines de RegExp
//  et, sur 20 000 chaînes, fige la box au premier caractère.
// =========================================================

/// Minuscules, sans accents latins courants, sans apostrophes.
/// Les espaces sont conservés (la recherche est un « contient »).
String tvSearchKey(String s) {
  const String from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const String to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final StringBuffer b = StringBuffer();
  for (final int r in s.toLowerCase().runes) {
    // Apostrophe droite ou typographique : on la retire pour que
    // « lequipe » et « l'equipe » désignent la même chaîne.
    if (r == 0x27 || r == 0x2019) continue;
    final String ch = String.fromCharCode(r);
    final int i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Vrai si [query] (déjà saisie par l'utilisateur) apparaît dans le
/// nom brut ou dans la catégorie. Requête vide → aucun résultat
/// (l'écran affiche alors l'aide, pas toute la playlist).
bool tvChannelMatchesQuery(String name, String category, String query) {
  final String t = tvSearchKey(query.trim());
  if (t.isEmpty) return false;
  return tvSearchKey(name).contains(t) || tvSearchKey(category).contains(t);
}
