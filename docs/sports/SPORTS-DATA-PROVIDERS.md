# SPORTS-DATA-PROVIDERS — Fournisseurs : réel vs possible

## Intégré AUJOURD'HUI

### TheSportsDB (gratuit, clé publique `/3`)
- Où : `cloudflare/worker.js:502` — proxy + cache 10 min, clé côté serveur.
- Couvre : recherche d'équipes (tous sports/pays), 5 derniers + 5 prochains
  matchs par équipe, scores finaux, badges/logos.
- Limites RÉELLES : pas de flux d'incidents (buts, cartons) en push ; pas de
  minute en direct fiable ; quotas bas ; données parfois en retard.
- Conclusion : suffisant pour calendrier + résultats + favoris + rappels.
  **Insuffisant pour des alertes de but à la seconde.**

## POSSIBLES (documentés, PAS souscrits — décision owner requise)

| Fournisseur | Ce qu'il apporte | Ordre de prix (à vérifier au contrat) |
|---|---|---|
| API-Football (api-sports.io) | Fixtures, live minute + événements (buts, cartons), classements, cotes pré-match ; ~1 100 ligues | Gratuit 100 req/j (dev) ; ~30-300 $/mois selon volume |
| Sportmonks | Football + cotes, websocket live sur plans supérieurs | ~39-129 €/mois et + |
| TheSportsDB Premium | Livescores V2, plus de requêtes | ~10 $/mois (Patreon) — le moins cher pour du « live approché » |
| The Odds API | Cotes multi-bookmakers (1X2, O/U, BTTS…) | Gratuit 500 req/mois ; payant au-delà |
| Sportradar / Stats Perform | Qualité broadcast, licences officielles | Contrats entreprise (milliers €/mois) — hors périmètre actuel |

Points à vérifier AVANT toute intégration (exigés par le prompt) :
droit d'affichage et de redistribution, droit d'utiliser les logos,
fréquence de rafraîchissement autorisée, territoires couverts, quotas,
coût réel. Aucun scraping sans autorisation.

## Règles d'intégration (déjà en place / à respecter)

- Clé JAMAIS dans l'APK : toute clé vit dans le Worker
  (`wrangler secret put …`), l'app parle uniquement à
  `kSubscriptionBaseUrl` (`lib/features/sports/data/sports_repository.dart`).
- Abstraction fournisseur : les modèles internes (`SportTeam`, `SportEvent`)
  ne dépendent pas des ids TheSportsDB côté UI ; un fournisseur payant se
  brancherait dans le Worker sans toucher l'app (mêmes routes `/api/sports/*`).
- Anti-péremption : l'app affiche l'heure du dernier sync (téléphone :
  `sports_screen.dart`, icône sync) ; ne jamais présenter une donnée
  périmée comme du direct.
