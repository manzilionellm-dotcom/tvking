// =========================================================
//  tv_remote_ux_test.dart — Recherche et zapping (calcul pur)
// =========================================================
//  Pas de flux, pas de lecteur : on vérifie seulement que la
//  télécommande « tombe » sur la bonne chaîne et le bon texte.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_search_text.dart';
import 'package:tv_king/features/tv/core/tv_zap.dart';

void main() {
  test('recherche TV : les accents et apostrophes ne bloquent pas', () {
    expect(tvChannelMatchesQuery("Téléfoot", 'Sport', 'tele'), isTrue);
    expect(tvChannelMatchesQuery("L'Équipe", 'Sport', 'lequipe'), isTrue);
    expect(tvChannelMatchesQuery("L'Équipe", 'Sport', "l'equipe"), isTrue);
    expect(tvChannelMatchesQuery('TF1', 'Divertissement', 'tf'), isTrue);
    // La catégorie compte : « sport » trouve une chaîne dont le nom
    // ne contient pas le mot, mais dont le groupe oui.
    expect(tvChannelMatchesQuery('Canal 9', 'Sport FR', 'sport'), isTrue);
    expect(tvChannelMatchesQuery('TF1', 'Divertissement', '   '), isFalse);
    expect(tvChannelMatchesQuery('TF1', 'Divertissement', 'news'), isFalse);
  });

  test('zapping : on boucle en haut et en bas de la liste', () {
    expect(tvNextZapIndex(0, -1, 5), 4);
    expect(tvNextZapIndex(4, 1, 5), 0);
    expect(tvNextZapIndex(2, 1, 5), 3);
    // Une seule chaîne, ou liste vide : rester en place (pas de crash).
    expect(tvNextZapIndex(0, 1, 1), 0);
    expect(tvNextZapIndex(0, -1, 0), 0);
  });
}
