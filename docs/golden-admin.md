# Golden : activation administrateur et livraison en temps réel

Golden apparaît sur la fiche de l'appareil dans la liste du panel, pour le rôle
`super_admin` déjà utilisé par l'intégration Gold. Il ne figure pas dans les
apps. « Je teste » est entièrement masqué dans Zuno et 7 MOTION ; le fournisseur
démo reste verrouillé et `gold_trial_enabled=0` n'est pas modifié.

L'import brut de la version `a3f55171` est isolé dans la PR #147, avec ses
empreintes d'origine. Les modifications fonctionnelles restent dans la PR #146.
Le point d'entrée est toujours `gold.js`, enveloppant le bundle exporté vérifié.

## Confirmation et création

L'admin saisit la MAC `MK:…`, la durée 1, 3, 6 ou 12 mois et choisit un template
lu par l'action `bouquet` de l'intégration existante. Le premier bouton prépare
un devis de trois minutes. Un second clic confirme explicitement le coût.

Le coût affiché est le tarif administrateur `gold_cost_per_month` multiplié par
la durée, identifié comme tel dans l'interface. Ce réglage doit exister
explicitement : aucun prix par défaut n'autorise un achat. Ce n'est pas un devis
tarifaire signé par Strong ; aucun endpoint de tarification n'a été inventé.
Le solde est lu avant la création et le plancher `gold_min_credits` est respecté.

Manzi8 est choisi en premier, puis manzi10 seulement pendant les vérifications
avant achat. Une fois le devis confirmé, la clé ne change plus. L'unique création
réutilise l'appel présent dans le wrapper exporté : `action=new`, `type=m3u`,
`sub=1|3|6|12`, `pack=<template choisi>`, `note=<identifiant de suivi>`.

Un registre D1 lie le devis à l'administrateur, à la MAC, au template, à la
durée, au coût, à la clé et à la version des listes. Un verrou par MAC et un
verrou par clé empêchent les achats concurrents. Un résultat incomplet ou un
timeout reste `uncertain` sans expiration automatique ni passage à la clé
suivante. Aucun nouvel achat n'est déclenché par un polling ou un nouvel essai
de livraison. La résolution d'un état incertain demande une vérification manuelle.

L'activation classique d'une licence et l'ancien provisionnement payant ne
déclenchent plus de création Strong en arrière-plan. Les renouvellements
administrateurs historiques restent une opération distincte.

## Publication et accusés

La ligne M3U renvoyée par Strong est chiffrée avec la primitive `enc1` existante,
puis ajoutée sans supprimer les autres listes (maximum trois). Une suppression
ou modification concurrente bloque la publication. La licence est activée via
le handler de production avec une clé d'idempotence ; une licence à vie est
préservée. La source et la licence sont poussées par `RT_HUB`.

Le panel indique « appliqué » seulement après les deux accusés de l'appareil,
avec la bonne révision de source. `delivered` côté registre signifie seulement
que la publication serveur est terminée. La reprise « livraison uniquement »
ne contacte jamais Strong. Les lectures des accès d'une ligne Golden exigent
le secret appareil, en plus de sa MAC et de l'identité enregistrée.

Les réglages globaux (thème, accueil, tarifs, mise en avant, publicité, invitation
d’avis, serveurs et seuil de mise à jour) publient aussi un ordre par appareil.
Les relectures réseau de réglage ne peuvent plus confirmer un ancien cache en cas
d’échec HTTP. Le téléphone applique maintenant chaque réglage ciblé avant son accusé.

Le canal partagé conserve heartbeat, reconnexion 1 à 30 s et repli HTTP toutes
les 5 s. L'import réel d'un catalogue dépend aussi du serveur M3U et de sa taille :
les mesures de recette ne constituent pas une garantie pour tout catalogue réel.

## Migration et vérifications

`20261029_golden_admin.sql` ajoute seulement les registres `golden_orders` et
`golden_key_locks`. Les migrations précédentes d'identité/reçus sont requises.
Aucune migration n'est exécutée automatiquement en production.

Les tests utilisent des clés et réponses fictives, jamais de création Strong
réelle : coût/confirmation, ordre des comptes, double clic, incertitude durable,
tarif modifié, identité réattribuée, listes concurrentes, licence à vie,
chiffrement, lecture protégée et suppression sans résurrection.

```sh
node --test android-app/cloudflare/tests/golden_admin.test.mjs
cd android-app/cloudflare
node --test tests/gold_realtime.test.mjs
```

La recette Chrome utilise le vrai panel compilé et un Worker/DO local, et retient
l'accusé source pour prouver que le succès n'apparaît pas prématurément. La recette
Android exécute le transport, SQLite et les widgets des deux apps ; le seuil de
2 000 ms comprend la confirmation simulée, l'import et les deux accusés. Strong
est simulé dans ces tests, l'API de production n'est pas appelée.
