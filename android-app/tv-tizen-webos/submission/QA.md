# Vérifications — 15 octobre 2026

## Effectué

`node --test tests/smoke.cjs` : 5 tests réussis.

1. Licence payée/essai valide, essai expiré, bannissement et gel prioritaires.
2. M3U : virgules dans les attributs et titres, rejet des schémas non HTTP(S).
3. Identité d’installation stable entre appels, sans privilège réseau partenaire.
4. Arrêt pendant préparation AVPlay : un callback tardif ne redémarre pas la vidéo.
5. Parcours avec DOM et API simulés : heartbeat → plusieurs sources (dont une en panne) → catégorie `__proto__` → titre HTML traité comme texte → lecture → retour → popup sortie → annulation → gel de licence périodique.

`bash build.sh` : réussi. Analyse syntaxique Node de tous les fichiers JS et copie des ressources.

Manifeste : XML analysé, profil `tv-samsung`, références `index.html` et `icon.png` présentes.

`git diff --check` : réussi.

## Limites

- Aucun test sur Samsung réelle ni émulateur Tizen ; aucun certificat disponible et CLI Tizen absent. Aucun WGT signé produit.
- Test navigateur Playwright tenté mais non exécuté : aucun moteur installé, téléchargement Chromium indisponible (archive invalide). Les tests de DOM simulé ne constituent pas une validation visuelle ou une mesure du focus physique.
- Backend, licences et sources réels non testés ; aucun client créé au panel par ces tests.
- Icône Z provisoire incluse ; visuels store, quatre captures réelles, document Samsung UI Description, politique de confidentialité et coordonnées éditeur à finaliser.
- Le client ne couvre que le direct, pas la parité complète Flutter.

Statut de publication : **non soumis**. Voir SAMSUNG.md pour la matrice de validation matérielle et les pièces restantes.
