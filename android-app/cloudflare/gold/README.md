# Import du Worker Gold en ligne

Copie de `gold-export.zip` fournie par le propriétaire, version déclarée
`a3f55171-173c-4a91-bfa9-1a347db085a4` du 26 octobre 2026, 17:59:53 UTC.
Empreinte SHA-256 du ZIP :
`a59522fba4e2c4bfb289fff04c8b8cff837ac23273dd86ffc5c7daca22155de9`.

Le premier commit de cette branche importe sans modification les octets de
`src/gold.js`, `src/worker.js` et `config/`. Le fichier `wrangler.toml` est
initialement une copie exacte de `config/wrangler.reconstitue.toml`.
Les adaptations et vérifications sont dans un second commit distinct.

`gold.js` est le point d'entrée et importe le `worker.js` voisin, issu du ZIP.
L'ancien `../worker.js` du dépôt n'est ni utilisé ni remplacé. Les deux fichiers
JavaScript restent identiques à l'archive, sans reformattage.

| Fichier | SHA-256 |
| --- | --- |
| gold.js | ff9cd709565169eef17a0b14ec7138f580bcf1e99e6fb838bfa1f3ebf38e6f96 |
| worker.js | ad08c5e6516c5741b686661e8ed35d16c1f9d1b20aadc164e14dc9a49628f71c |

Les bindings sont `DB` → D1 `tvking_licensing` et `RT_HUB` → `RealtimeHub`.
Les secrets du rapport sont des marqueurs masqués ; aucune valeur n'est ajoutée.
La migration DO reconstruite n'a pas de type historique confirmé dans l'export :
le second commit la retire du `wrangler.toml` utilisable, en conservant l'original
dans `config/`. Aucun schéma D1 n'est appliqué par cet import.

Vérification locale, sans réseau ni déploiement :

```sh
node android-app/cloudflare/gold/verify-import.mjs
```

Le workflow ajouté ne fait que ces contrôles sur PR. Aucun workflow de
déploiement n'est ajouté. Cette PR est une base fidèle pour les modifications
Golden et temps réel, pas une activation de ces fonctionnalités en production.
L'archive atteste l'export fourni, pas la version actuellement active sur Cloudflare.
