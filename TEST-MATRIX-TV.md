# TEST-MATRIX-TV — DEFEW TV

Suite : `flutter test test/features/tv`. Le rendu réel (D-pad, télécommande,
box) n'est pas automatisable ici — protections de code listées, à valider sur
box.

## Couverture automatisée (TV)

| Domaine | Fichiers | Vérifie |
|---|---|---|
| Contrainte build | **tv_media_kit_import_guard (NOUVEAU)** | 0 media_kit dans la fermeture de main_tv.dart |
| Focus | tv_focusable_test | focus/OK/zoom/flèches |
| États | tv_skeleton_test, tv_live_preview_test | squelettes, « zéro spinner », aperçu |
| Machines à états lecteur | freeze_recovery_policy, stream_stability_monitor, autoplay_policy, quality_ladder | anti-gel, stabilité, autoplay, échelle qualité |
| Perf | cine_perf_test | budgets (accueil/fiche/TTFF) |
| Erreurs | failure_explainer, playback_failure_log, native_track_contract | messages, journal, contrat pistes |

## Séquences agressives télécommande (protection → à valider box)

| Séquence | Protection en place | Attendu |
|---|---|---|
| Haut/bas très rapide | zap différé 150 ms sans connexion | pas de saturation, focus jamais perdu |
| Gauche/droite rapide | débounce catégorie 220 ms / aperçu 120 ms | fluide |
| Ouverture/fermeture répétée d'écrans | verrou `openTvPlayer` (audit T-M4) | jamais 2 lecteurs |
| Changement rapide de catégorie | anti-rebond aperçu 600 ms + répit 1,8 s | pas de rafale de connexions |
| Lancement/fermeture répétée du lecteur | pause+libération avant push (T-C1) | 1 seule connexion amont |
| Bouton retour depuis l'accueil | dialogues avec autofocus + l10n (T-M3) | OK répond |
| Navigation après plusieurs heures | veille anti burn-in sur 4 templates (T-M5) | pas de marquage OLED |
| Perte/retour réseau | FreezeRecoveryPolicy + StreamStabilityMonitor | reconnexion, pas d'écran d'erreur définitif |
| Mise en veille / reprise | watchdog suspendu en veille, flux rechargé au réveil (T-H1) | image au réveil, pas d'erreur |

## Gros catalogues (protection → à valider box)

| Volume | Protection | Vérifier |
|---|---|---|
| 1 000 | pagination keyset 150/page, ListView.builder | chargement, scroll, recherche |
| 5 000 | plafonds RAM adaptatifs, cache images plafonné | mémoire, fluidité |
| 15 000 | index SQLite v7, préchargement borné | navigation, recherche répétée, zap |
| 30 000 | idem + `DeviceMemory.channelCap` | tenue mémoire (reste connu : Modèles C/D hors pagination → B-19) |

Focus jamais perdu · aucun écran impossible à quitter · aucune rafale de
télécommande ne provoque saturation/crash/boucle : garanti par le code aux
chemins audités ; **à confirmer sur box réelle** (aucune box dans
l'environnement de dev — mesures via Boîte noire tag « perf »).
