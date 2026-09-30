# Sécurité Zuno — ce qui a changé

Ce document explique les correctifs de la branche `claude/zuno-securite`.
Aucune valeur de secret n'y figure.

## Ce que les box déjà installées continuent de faire

- Une box qui n'a **pas** encore cette mise à jour reçoit toujours ses
  chaînes avec `GET /api/device-source/<MAC>`, **si** elle est déjà
  connue dans la base et que sa licence se lit, et n'est pas expirée,
  gelée ou bannie. Une MAC inconnue ne reçoit plus les codes.
- Si la base ne répond pas, le serveur **ne renvoie plus** les mots de
  passe. L'application garde les chaînes déjà en mémoire.
- La sauvegarde cloud (`/api/backup`) ne répond plus avec la seule MAC.
  L'ancienne application verra un refus : ses listes **locales** restent.
  La restauration cloud reprend après la mise à jour de l'application.

## Nouveau contrat (application mise à jour)

1. Au démarrage, l'application crée un secret et l'envoie à
   `POST /api/device-proof` avec la MAC et l'identifiant Android.
   Le serveur ne garde que l'empreinte.
2. Ensuite, `GET /api/device-source`, `GET/PUT /api/backup` et le
   diagnostic envoient le header `X-Device-Secret`.
3. Dès qu'une empreinte existe pour cette MAC, une requête **sans**
   ce secret ne reçoit plus les codes (401).
4. Une réinstallation : l'identifiant Android est le même, le secret
   local est neuf. Le serveur accepte le nouveau secret. Quelqu'un
   qui n'a vu que le code à l'écran ne le peut pas.

## Panneau

- Si `ADMIN_SECRET` n'est pas posé dans Cloudflare, la connexion
  répond 503 `admin_unconfigured`. Il n'y a plus de clé de secours
  dans le code, ni de mot de passe maître qui réécrit le compte.
- Le premier compte, si la table est vide, est créé avec ce secret
  comme mot de passe **uniquement** lorsqu'il est configuré.
- Changer `ADMIN_SECRET` ensuite ne change **pas** le mot de passe
  d'un compte déjà créé. On le change dans « Mon compte ». Si le
  mot de passe est perdu et que ce compte est le seul : vider la
  table des comptes admin, puis relancer le workflow qui pose
  `ADMIN_SECRET` pour recréer le premier compte.
- Un revendeur ne peut plus lire ni modifier la fiche ou les sources
  d'une box qui n'est pas dans son stock (403).

## Chiffrement

- Sur la box : les mots de passe Xtream et les liens M3U sont chiffrés
  dans SQLite (`enc1:`). Les anciennes lignes en clair restent lisibles.
- Sur le serveur : pareil dans D1, **seulement** si le secret
  `SOURCE_ENCRYPTION_KEY` est posé. Sans cette clé, les lignes restent
  en clair (on n'invente pas de clé dans le code). L'application reçoit
  toujours le mot de passe en clair dans la réponse HTTPS : il lui faut
  pour ouvrir la liste.

## Mise à jour de l'application

`version.json` doit contenir `sha256` et `size`. Sinon cette version
de l'application ne propose pas la mise à jour (elle continue de
fonctionner). Les workflows de publication écrivent ces deux champs
lors du **prochain** lancement. Rien n'est publié par ce correctif.

## Ordre à suivre par le propriétaire

1. Dans Cloudflare, vérifier que `ADMIN_SECRET` est bien posé.
   Ne pas le copier ici.
2. Poser un nouveau secret `SOURCE_ENCRYPTION_KEY`
   (`wrangler secret put SOURCE_ENCRYPTION_KEY`, une longue valeur
   aléatoire). Ne pas la commiter. Ne pas la retirer ensuite : les
   lignes chiffrées avec elle ne se reliraient plus.
3. Comparer le Worker **en ligne** avec ce dépôt avant de déployer
   (`worker-prod-snapshot.yml` : la production peut être en avance).
   Ne pas déployer tant que cet écart n'est pas compris.
4. Déployer le Worker **avant** ou **en même temps** que l'application.
   Les box actuelles gardent leurs chaînes. La sauvegarde cloud des
   anciennes applications s'arrête jusqu'à leur mise à jour.
5. Installer l'application d'abord sur **une box de test**.
   Ne pas mettre `publish=true`. Ne pas écrire sur la release `zuno-tv`
   tant que la box de test n'a pas installé le build.
6. Au moment de publier pour les clients, le `version.json` doit
   inclure `sha256` et `size` (les workflows le font maintenant).

## Ce qui reste

- Tant qu'une box n'est pas mise à jour, quelqu'un qui voit son code
  MAC peut encore **lire** la source si la box est connue et que la
  licence est valide. L'écriture de la sauvegarde, elle, est déjà
  fermée. C'est le prix de ne pas couper les box déjà installées.
- « Mon espace » (site) peut encore modifier les listes personnelles
  d'une box **pas encore** enrôlée. Dès que le secret est enregistré,
  ces modifications exigent le secret : elles se font sur la box.
- Les liens famille (`/api/m3u/<jeton>`) restent protégés par le jeton,
  pas par le secret de box. Le mot de passe y est encore en clair dans
  la table des familles.
- Le guide TV, le replay, la recherche tolérante, les deux profils et
  la mesure d'usage ne font pas partie de ce correctif.
- Le son, le décodeur et `NativeVideoView.kt` n'ont pas été touchés.
