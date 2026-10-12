# Passation — branche panel, 11 octobre 2026

Cette fiche est ajoutée sur la branche panel, où ce chemin était absent
au commit `d81da1a8e3231e951d4a836f9b05e0d4806a9cdf` (lecture GitHub : 404).
La passation historique de la branche app reste distincte : ne pas fusionner
aveuglément les deux branches pour recopier leurs documents ou leur code.

## Publicités et événements

PROUVÉ localement — nouvelle page propriétaire, brouillons privés, aperçu,
pays, dates avec fuseau, programmation, pause/reprise, duplication et archivage.
`node --test cloudflare/campaigns.test.mjs` depuis `android-app` : 10/10
tests rouges avant ajout, puis 13/13 verts. `npm test` dans `admin-panel` :
72/72 verts ; `npm run build` réussi. Suite Worker complète : 42/42 entrées
du lanceur Node réussies ; audit de sécurité existant : 47/47 contrôles.

PROUVÉ en CI — code `2734584`, parcours navigateur et workerd
[38162131019](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38162131019)
vert : brouillon, programmation, douze lecteurs concurrents sans doublon,
pause/reprise, duplication et largeur mobile. Les tests existants passent aussi.

NON PROUVÉ — déploiement du module et affichage sur la SHIELD. Les branches de production restent
gelées. Aucun fichier Flutter, APK, AAB ou catalogue client n'est modifié.

Les preuves, limites, sources documentaires, procédure de mise en ligne et
retour arrière sont dans [PUBLICITES-EVENEMENTS-20261011.md](PUBLICITES-EVENEMENTS-20261011.md).

## Reprise du 12 octobre 2026

Deux chemins historiques pouvaient contourner l'arrêt des campagnes : retrait
global laissant les campagnes futures programmées, et bouton d'annonce
réactivant une campagne en pause/archivée. Défauts reproduits puis corrigés
sur la branche de la PR 110, avec trois scénarios de régression.

PROUVÉ localement : campagnes 16/16, suite Worker 45/45 entrées, panel 72/72,
sécurité 47/47, protections 30/30 et build panel réussi. Résultat CI de la
nouvelle tête à vérifier sur la PR avant intégration. Production toujours
gelée, aucun déploiement lancé. La preuve physique sur TV reste à recevoir.
