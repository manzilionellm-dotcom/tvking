# Simulation Zuno 107 — 13 octobre 2026

Le parcours fonctionnel du client publié a réussi face au Worker référencé par
le gel de production. Aucun code de l'application ou du panel n'a été modifié,
aucun service public n'a été déployé et aucun appareil client n'a été activé.

## Preuve et périmètre

- Exécution réussie : https://github.com/manzilionellm-dotcom/tvking/actions/runs/38365681210
- Scénario testé : `cdfa552ddfafabbdbabf773ab28f55d945795999`.
- Code du client Zuno 107 : `fa7fa00661f79dea1997c4782c76f8265eaf7200`.
- Worker référencé : `fb0277e1f5476db3400100c4fe4163b1b9ef1fe3`.
- Panel référencé : `719928dc92c8827365815a0cd482cb903a8a3e7e`.

Les deux références serveur/panel viennent de `.github/panel-production.json`
dans `d81da1a8e3231e951d4a836f9b05e0d4806a9cdf`. Leurs déploiements enregistrés
avaient réussi. Cela ne constitue pas une interrogation de la version actuellement
servie par Cloudflare.

Le test fonctionnel exécute les vrais `RemoteActivationWatch`,
`SubscriptionState`, `RemoteSourceRepository` et `PlaylistRepository` :
HTTP, WebSocket, import, SQLite, mise à jour des snapshots de chaînes et accusés.
Les préférences Android sont simulées et SQLite utilise son moteur FFI.
Un fournisseur HTTP local sert uniquement des données synthétiques.
Aucune chaîne n'est injectée directement en base par le scénario.

Les commandes passent par l'API utilisée par le panel. La colonne « confirmation »
mesure la lecture de l'accusé persisté côté serveur, pas le rafraîchissement visuel
d'un navigateur. Le vrai navigateur du panel est couvert séparément ci-dessous.

## Mesures de cette exécution

| Opération | État obtenu dans le client | Confirmation serveur |
| --- | ---: | ---: |
| Activation | 0,134 s | 0,253 s |
| Import M3U, 3 chaînes | 0,259 s | 0,367 s |
| Lien get.php traité via Xtream, 5 chaînes | 0,193 s | 0,216 s |
| Refus explicite du fournisseur, ancienne liste conservée | Vérifié | 0,138 s, FAILED |
| Remplacement après le refus, 4 chaînes | 0,133 s | 0,224 s |
| Reprise de l'app avec un ordre en attente | Vérifié | 0,170 s après reprise |
| Reprise après redémarrage du Worker local | Vérifié | 0,316 s après reprise du client |
| Effacement des listes et chaînes | Vérifié | 0,180 s |

Le délai d'indisponibilité et de démarrage du Worker n'est pas inclus dans la
mesure de reprise. Ces observations portent sur un seul passage, de petites
listes, une machine de CI et des échanges en boucle locale. Elles ne prédisent
pas le délai d'une grande playlist, d'Internet ou d'une télévision physique.

Contrôles effectivement exécutés :

- L'identifiant de la box reste identique du début à la fin.
- Les chaînes téléchargées sont présentes dans les snapshots et SQLite.
- Le lien `get.php` emploie l'API Xtream ; aucun téléchargement M3U de repli
  n'est effectué lorsque l'API fonctionne ou refuse explicitement le compte.
- Un refus produit un accusé `failed / refused_kept_previous`, conserve les
  cinq chaînes et n'ajoute aucune playlist orpheline.
- Un ordre en attente reste `created` ou `sent` lorsque l'app est arrêtée.
- La reprise importe l'ordre et persiste son accusé réel `applied`.
- Les révisions appliquées correspondent aux révisions envoyées.
- L'effacement retire les chaînes de SQLite sans couper la licence.

Une tentative secondaire de traitement est journalisée en erreur réseau au
moment de l'arrêt volontaire du Worker. L'ordre avait déjà été confirmé
`applied` ; la transition terminale reste protégée. Le scénario de reprise
suivant réussit. Le journal complet est conservé dans l'artefact du workflow.

## Vérification complémentaire du panel

Exécution de diagnostic :
https://github.com/manzilionellm-dotcom/tvking/actions/runs/38364871594

Le job « Panel référencé — navigateur et box simulée » réussit. Il utilise
Chromium, le vrai panel, un Worker local et une box HTTP simulée. Il vérifie
notamment connexion, activation, ajouts/remplacements de sources, suivi
`received / failed / applied`, présence en ligne, effacement et expiration.
Ce job ne télécharge pas les chaînes et ne fait pas tourner le client Flutter.

Le même workflow de diagnostic reste **en échec global** : les deux anciens
tests Dart, écrits pour le serveur de la branche app, ne correspondent pas
entièrement au contrat du Worker référencé :

1. `panel_box_e2e_test.dart` attend `source_rev` dans le statut. Le Worker
   référencé fournit la révision dans la réponse des sources et les ordres.
   L'activation a été mesurée à 0,297 s avant cette attente dépassée.
2. `panel_instant_e2e_test.dart` attend un HTTP 401 pour l'attente sans secret
   d'appareil ; le Worker référencé renvoie 200. C'est une différence réelle
   d'authentification à traiter séparément, pas une validation de sécurité.

Ces tests réussissent tous deux avec le serveur présent dans la branche app,
qui utilise le repli par attente longue (WebSocket 404 dans ce scénario).
Le nouveau test fonctionnel est indépendant : il n'assouplit ni ces assertions
ni les protections du serveur. Un résultat vert fonctionnel ne résout pas
l'écart d'authentification observé.

## Limites et données client

Le téléchargement de la playlist privée fournie pour l'essai a été refusé par
l'environnement de travail. Aucun identifiant de cette playlist n'a été copié
dans le dépôt, les workflows ou les artefacts. Son abonnement, ses chaînes et
la lecture vidéo/audio ne sont donc pas validés par cette simulation.

Ce test n'installe pas l'APK dans un émulateur Android et ne mesure pas une TV
physique. Il valide le code de communication et d'import correspondant à Zuno
107, avec son comportement réel et un fournisseur local contrôlé.

## Reproduction

Le workflow `.github/workflows/zuno107-functional-simulation.yml` assemble les
références immuables, copie ce test dans le dossier de tests du client publié,
installe les dépendances puis exécute :

```sh
flutter test --reporter expanded \
  --dart-define=RUN_E2E=true \
  --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
  test/features/subscription/zuno107_reference_e2e_test.dart
```

Le Worker s'exécute uniquement avec `wrangler dev --local`, une D1 temporaire
et des secrets synthétiques. Aucun secret de production n'est nécessaire.
