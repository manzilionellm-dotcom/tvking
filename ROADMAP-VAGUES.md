# 🌊 ROADMAP — 30 petites vagues vers l'application futuriste

> Méthode : petites vagues indépendantes, chacune vérifiée par le CI
> (analyze + tests + Simulateur TV) avant la suivante. Notes honnêtes,
> jamais de complaisance. Ce fichier est LA mémoire du plan — n'importe
> quelle session (humaine ou Claude) reprend ici.
>
> État : `[x]` fait · `[~]` en cours · `[ ]` à faire

## Bloc A — Stabilité visuelle & qualité d'image (« comme Netflix »)

- [x] V1. Images nettes partout : fade-in doux, placeholders stables (zéro
  saut de mise en page), résolution de cache adaptée à la taille réelle
  des tuiles, erreurs d'image silencieuses → monogramme propre.
- [~] V2. Squelettes de chargement (shimmer sobre) sur accueil/rails TV et
  mobile — plus jamais de spinner nu ni d'écran qui « pop ».
- [ ] V3. Transitions d'écran cohérentes (fade/slide léger, 150-200 ms) et
  uniformes entre templates.
- [ ] V4. Affiches VOD haute résolution quand le panel/Xtream les fournit
  (choisir la meilleure URL d'image disponible).
- [ ] V5. Barre de progression et badges (HD/4K/langue) sur les tuiles
  quand l'info existe.
- [ ] V6. Anti-jank : audit des rebuilds inutiles (ListenableBuilder trop
  larges), const partout où possible sur les chemins chauds.
- [ ] V7. Corriger les 4 bugs découverts par le Simulateur (autofocus
  TiviMate vide, ligne EPG jamais rafraîchie, TTL « now » 60 s,
  en-tête 200 px qui déborde).
- [ ] V8. Mode faible bande passante : qualité d'image réduite
  automatiquement quand le réseau rame (déjà détecté par l'app).
- [x] V9. Écrans d'erreur « à la Netflix » : illustration + action claire,
  jamais de texte technique brut.
- [ ] V10. Polissage typographique : échelle cohérente, contrastes AA,
  textes tronqués proprement partout.

## Bloc B — Intelligence client (l'app apprend ce qu'on aime)

- [x] B11. Rangée « Pour toi » sur l'accueil mobile branchée sur
  l'affinity_service existant (il tournait dans le vide depuis la mort
  de l'ancien HomeScreen).
- [x] B12. « Pour toi » côté TV (template Classique d'abord).
- [ ] B13. Reprise intelligente : « Tu regardais X hier soir à cette
  heure-ci » (time_of_day_service existe déjà).
- [ ] B14. Suggestions par moment de la journée (sport le week-end,
  dessins animés le matin si profil enfant).
- [ ] B15. « Nouveautés pour toi » : croiser vod_novelty_service avec les
  goûts (vod_taste) — badge NOUVEAU pertinent.
- [ ] B16. Recherche : boost par historique personnel (déjà partiel dans
  smart_search — compléter et tester).
- [ ] B17. Notifications intelligentes : « Ton équipe joue dans 30 min »
  (rappels EPG × favoris × habitudes).
- [ ] B18. Profil de goûts visible : « Tes genres préférés » dans le
  profil, avec option d'effacement (transparence).
- [ ] B19. Télémetrie d'usage OPT-IN vers le panel (agrégée, anonyme par
  MAC, respectueuse) : top chaînes, heures de pointe — la matière
  première du panel intelligent.
- [ ] B20. Tests du bloc B dans le Simulateur (les recos apparaissent,
  changent avec l'historique, respectent le mode Enfants).

## Bloc C — Panel admin intelligent

- [x] C21. API worker : endpoint « insights » (agrégats des heartbeats
  existants : appareils actifs/jour, nouveaux, silencieux, versions). ✅ EN PROD
- [x] C22. Panel : tableau de bord « Ce qui s'est passé » à la connexion
  (nouveautés, comportement du parc, alertes) — la demande exacte du
  patron. ✅ EN PROD
- [x] BONUS. 🔬 Labo du Maître : sources M3U privées et étanches, copiées
  auto sur les appareils maîtres, exclues des stats. ✅ EN PROD
- [ ] C23. Panel : santé du parc (erreurs remontées par error-log,
  boîtes noires, versions APK en circulation).
- [ ] C24. Panel : top contenus (dès que B19 alimente les données).
- [x] C25. Alertes proactives : « 12 boxes n'ont pas donné signe de vie
  depuis 7 jours », « 3 clients expirent cette semaine ».
- [ ] C26. Rapport hebdo automatique (résumé simple, envoyé/affiché).

## Bloc D — Futuriste

- [ ] D27. Recherche vocale/naturelle étendue (l'ai_search_service existe
  — l'amener sur TV et l'enrichir du contexte personnel).
- [ ] D28. « Zapping intelligent » : bouton « surprends-moi » qui ouvre la
  chaîne la plus probable selon l'heure et les goûts.
- [ ] D29. Résumé de match / prochain épisode : cartes contextuelles
  au-dessus du lecteur (EPG + habitudes).
- [ ] D30. Assistant intégré : « Pose une question » (guide TV en langage
  naturel via le worker — clé serveur, jamais dans l'app).

## Règles permanentes

1. Une vague = un commit lisible = validée par le CI avant la suivante.
2. Le Simulateur TV doit rester vert — il protège tout le reste.
3. Aucune donnée client sans opt-in et sans transparence (B18/B19).
4. Les notes /10 restent honnêtes : mesurées, jamais offertes.
