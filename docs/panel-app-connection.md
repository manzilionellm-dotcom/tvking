# Connexion atlas-console → applications

Le parcours vérifié est `/activate` → Worker Gold → licence / préparation
fournisseur → ordre `source` → lecture de la liste par l'app → accusé.
Le serveur de production exporté utilise `/api/box/ws`, `/api/box/wait/:mac`
et `/api/box/ack/:mac`. Une réponse 201 d'activation confirme la licence,
pas la création fournisseur ni le chargement des chaînes.

## Défauts corrigés

- Zuno annulait son minuteur de secours lors d'un ordre, sans le réarmer.
  Le filet continue après chaque ordre et reprend immédiatement si le canal
  tombe ; une reconnexion déclenche une relecture immédiate du statut.
- Le client WebSocket avançait son numéro avant de savoir si l'ordre avait
  été appliqué. Il ne le valide plus en cas de panne et ferme les connexions
  muettes / retardataires. La preuve appareil reste dans les en-têtes.
- Zuno attend également la confirmation de chaque accusé final, y compris
  dans une réponse HTTP 200 contenant plusieurs résultats. Une réponse
  perdue ou un refus individuel ne fait plus oublier l'ordre au panel.
- Les curseurs Zuno sont associés à leur MAC. Les anciens curseurs globaux
  ne peuvent pas masquer les premiers ordres d'une autre MAC.
- Le téléphone recevait déjà les ordres par attente longue, mais ne renvoyait
  pas les accusés du protocole `box_orders`. Il confirme désormais réception,
  application et révision ; un refus individuel dans un HTTP 200 ne compte
  pas comme succès. Il conserve le curseur après un échec.
- L'état FAILED est définitif dans ce Worker. Les coupures récupérables
  restent RECEIVED pendant la reprise, puis deviennent APPLIED.
- Un import mobile partiel ne cache plus l'échec d'une des listes derrière
  la réussite d'une autre. Le statut est relu après réception de l'ordre.
- Le panel n'annonce plus « appareil activé » sur la seule écriture de
  licence : il suit séparément licence, préparation et réception de liste.
  Son suivi lit les ordres toutes les secondes, sans lectures concurrentes,
  s'arrête à confirmation et se suspend en onglet caché.
- Une panne d'envoi après activation permet de renvoyer uniquement les
  listes. La licence n'est pas recréée ni redébitée. Une réponse d'activation
  perdue impose de vérifier la fiche avant de faire une nouvelle demande.
- Sans `VITE_API_BASE`, un build de production du panel vise le même Worker
  que Zuno (`https://app.7themotion.com`), au lieu d'une route `/api` du site
  Vercel pouvant renvoyer du HTML. La surcharge explicite et le proxy de
  développement restent disponibles. Les réponses HTML 200 sont rejetées.
- Le formulaire respecte la limite de trois sources du bundle exporté ;
  il ne propose plus six sources dont les trois dernières seraient ignorées.

## Préparation fournisseur

Le hook payant existant continue après l'activation de licence. Il écrit
désormais ses étapes dans `gold_history`, liées à la trace de l'activation.
`GET /api/v1/activation-delivery?mac=…&trace=…` expose uniquement des états
et messages français fixes, après authentification et contrôle du revendeur.
Les règles de création payante ne changent pas et aucun appel fournisseur
n'est ajouté au suivi. Aucun paquet d'essai non vérifié n'est activé.

Le renouvellement existant conserve sa liste ; le statut `renewed` ne
prétend donc pas qu'une nouvelle liste a été envoyée. Le suivi distingue
une préparation échouée d'une liste écrite mais encore non confirmée.

## Vérification

- Tests Node sur le vrai schéma exporté : auth, isolation MAC/trace,
  messages sans secrets, ordre chronologique des étapes, absence de double
  activation après panne, et comparaison de la révision appliquée.
- Tests Flutter sur de vraies prises WebSocket locales : échec puis reprise
  du même ordre, doublons, mauvaise MAC, arrêt de la session.
- Régression Zuno avec serveur HTTP local : activation reçue, canal coupé,
  puis gel appliqué par le filet sans relancer l'app. Exécution dédiée CI
  avec `RUN_PANEL_CONNECTION=true` et `BACKEND_URL=http://127.0.0.1:18789`.
- Téléphone : reçus avant/après import, révision, preuve en en-tête,
  maintien du curseur quand le serveur refuse un accusé.
- Chrome sur le panel compilé : panne de source après activation, reprise
  sans deuxième débit, révision confirmée, arrêt du suivi, formulaire
  suivant et affichage mobile sans débordement. Toutes les API sont simulées.

## Vérification en ligne restant nécessaire

Le 28 octobre 2026, `/activate` redirige ici vers la connexion Vercel.
Le connecteur Vercel disponible ne voit pas ce projet. Les sondes réseau
publiques depuis cet environnement ne suffisent pas à mesurer le trajet
jusqu'à un appareil client ; elles ne prouvent pas une panne générale.
Aucune activation, ligne fournisseur ou donnée client de production n'a
été créée pour ces tests. Aucun déploiement n'est effectué.

Après publication autorisée : ouvrir les deux apps, envoyer une licence
et une petite liste de recette, vérifier RECEIVED puis APPLIED avec la
bonne révision, couper/rétablir le Wi-Fi, répéter pendant une lecture et
vérifier la suppression. Pour la voie automatique, vérifier aussi les
étapes de préparation de la ligne et son historique avant de réessayer.
L'objectif de 1–2 secondes concerne la notification et la confirmation
rapide d'un appareil connecté ; le téléchargement/analyse d'une grosse
liste et le délai fournisseur doivent être mesurés séparément.

Aucune nouvelle migration n'est nécessaire pour ce correctif : les étapes
utilisent `gold_history` et les reçus utilisent `box_orders` existants.
Les migrations Gold additives documentées dans la PR restent nécessaires
pour les autres fonctions de l'essai.
