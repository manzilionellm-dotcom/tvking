// =========================================================
//  tv_home_template_test.dart — Les deux modèles d'accueil
// =========================================================
//  Décision client du 2026-08-01 (deuxième temps) : « je veux que B soit
//  l'app primordiale et A l'app secondaire ». L'accueil à menu latéral
//  (identifiant technique `iptv`) devient donc le MODÈLE A et l'accueil
//  par défaut ; l'ancien accueil (`classic`) devient le MODÈLE B.
//
//  Ce qui est vérifié ici :
//    1. les noms affichés sont bien inversés ;
//    2. les IDENTIFIANTS techniques n'ont PAS changé — sinon le choix
//       déjà enregistré sur la box du client serait perdu au prochain
//       démarrage ;
//    3. la pastille de bascule ne propose jamais le modèle courant ;
//    4. les deux modèles partagent la MÊME liste de favoris — passer de
//       l'un à l'autre ne doit pas faire disparaître les cœurs.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

void main() {
  test('les noms sont inversés : le menu latéral est le Modèle A', () {
    expect(TvHomeTemplate.iptv.label, 'Modèle A');
    expect(TvHomeTemplate.classic.label, 'Modèle B');
  });

  test('les identifiants enregistrés ne changent PAS', () {
    // Une box qui a déjà « classic » ou « iptv » en mémoire doit rouvrir
    // sur le même accueil qu'avant l'inversion.
    expect(TvHomeTemplate.classic.id, 'classic');
    expect(TvHomeTemplate.iptv.id, 'iptv');
  });

  test('le Modèle A est le premier de la liste (sélecteur)', () {
    expect(TvHomeTemplate.values.first, TvHomeTemplate.iptv);
  });

  test('la pastille ne propose jamais le modèle courant', () {
    expect(otherTemplate(TvHomeTemplate.iptv), TvHomeTemplate.classic);
    expect(otherTemplate(TvHomeTemplate.classic), TvHomeTemplate.iptv);
  });

  test('les deux modèles partagent les mêmes favoris', () {
    // Avant l'inversion, chaque modèle avait sa propre portée : mettre le
    // menu latéral en accueil principal aurait vidé les favoris du client.
    expect(favoritesScopeForTemplate(TvHomeTemplate.iptv),
        FavoritesRepository.defaultScope);
    expect(favoritesScopeForTemplate(TvHomeTemplate.classic),
        FavoritesRepository.defaultScope);
  });
}
