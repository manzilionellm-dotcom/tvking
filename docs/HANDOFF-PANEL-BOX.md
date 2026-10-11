# Passation — branche panel, 11 octobre 2026

Cette fiche est ajoutée sur la branche panel, où ce chemin était absent
au commit `d81da1a8e3231e951d4a836f9b05e0d4806a9cdf` (lecture GitHub : 404).
La passation historique de la branche app reste distincte : ne pas fusionner
aveuglément les deux branches pour recopier leurs documents ou leur code.

## Publicités et événements

PROUVÉ localement — nouvelle page propriétaire, brouillons privés, aperçu,
pays, dates avec fuseau, programmation, pause/reprise, duplication et archivage.
`node --test cloudflare/campaigns.test.mjs` depuis `android-app` : 10/10
tests rouges avant ajout, puis 12/12 verts. `npm test` dans `admin-panel` :
72/72 verts ; `npm run build` réussi. Suite Worker complète : 41/41 entrées
du lanceur Node réussies ; audit de sécurité existant : 47/47 contrôles.

NON PROUVÉ à cette étape — nouveau parcours navigateur en CI, déploiement
du module et affichage sur la SHIELD. Les branches de production restent
gelées. Aucun fichier Flutter, APK, AAB ou catalogue client n'est modifié.

Les preuves, limites, sources documentaires, procédure de mise en ligne et
retour arrière sont dans [PUBLICITES-EVENEMENTS-20261011.md](PUBLICITES-EVENEMENTS-20261011.md).
