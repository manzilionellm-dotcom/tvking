# Parcours local : panel, Worker, box simulée

Cette suite démarre **uniquement en local** :

1. le Worker (`wrangler dev --local`, donc miniflare et une base D1 vide) ;
2. le panel Vite, qui envoie `/api` vers ce Worker ;
3. un client HTTP qui fait les mêmes appels que l'app TV.

Aucun déploiement, aucun appel au site public, aucun secret dans le dépôt.
Le mot de passe admin est tiré au hasard à chaque lancement et n'est pas affiché.
Les liens M3U sont des adresses `127.0.0.1` : la suite ne les télécharge pas.

## Lancer

```bash
cd android-app/admin-panel && npm ci
cd ../e2e/panel-box && npm ci
npx playwright install chromium
npm run e2e
```

Le Worker écoute `127.0.0.1:8787`, le panel `127.0.0.1:5173`.
Ces ports doivent être libres.

## Ce qui est exercé

- Connexion admin (mot de passe faux, puis bon) depuis l'écran de login.
- Création et activation d'un client **sans** lien M3U, puis présence dans la liste Clients.
- Ajout d'un lien M3U, puis remplacement par un autre, **sans** toucher à la date de licence.
- Message instantané publié dans Annonces, relu par la box.
- Effacement de la liste : la box ne reçoit plus de lien, l'abonnement reste valide.
- Heartbeat, puis écran « En ligne » (MAC + chaîne annoncée).
- Expiration : `expires_at` placé dans le passé, la box est bloquée et ne reçoit plus le lien.

## Ce qu'une vraie box doit encore confirmer

- L'écran de la TV retire vraiment la liste déjà chargée. Le code de l'app
  garde la liste locale quand le serveur renvoie `source: null`.
- La lecture d'une vraie playlist, l'image, le son, le lecteur.
- Le pays et l'IP vus par Cloudflare.
- L'expiration en laissant l'horloge tourner, sans écrire la date à la main.
- Le site public `https://tvking-admin.pages.dev`.
