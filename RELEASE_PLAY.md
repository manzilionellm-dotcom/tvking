# RELEASE_PLAY.md — Resoumission Google Play de 7 MOTION

> Mémoire de release : pourquoi le refus, ce qui a été corrigé dans le code,
> comment resoumettre, et la checklist à dérouler avant CHAQUE envoi.
> Fiche Play : « Lecteur IPTV – 7 MOTION ». Prod actuelle : versionCode 1349
> (1.0.0, publiée le 2026-08-02).

---

## 1. Le refus (2026-08-05) et sa cause

Motif Console : « Exigences de Play Console » — identifiants de connexion /
accès à l'application insuffisants pour l'examinateur (précédent motif :
« authentifiants restreints par l'authentification de l'appareil »).

Cause réelle : la ligne de test déclarée était expirée, et le parcours
d'activation « numéro de référence → revendeur » ne permettait à aucun
examinateur d'entrer seul dans l'app. Le champ mot de passe de la
déclaration était vide.

## 2. Ce qui a été corrigé dans le code (branche `claude/google-play-review-line-jfu3q9`)

| Correctif | Où | Commit |
|---|---|---|
| Code examinateur `GPLAYREVIEW` (identifiant OU lien M3U) → bouquet démo EMBARQUÉ, zéro réseau, zéro activation | `demo_mode.dart` (`kReviewAccessCode`), `xtream_login_form.dart` | 20777f2c |
| Build Play sans AUCUN prix / essai / achat hors Play Billing (`--dart-define=PLAY_BUILD=true`, gardes `kIsStoreBuild`) | `build_flags.dart` + 10 surfaces UI | 20777f2c, b5745cd6 |
| Auto-updater sideload neutralisé en build store (+ permission `REQUEST_INSTALL_PACKAGES` retirée du manifeste AAB par le CI) | `update_*.dart`, `build-android.yml` | pré-existant |
| Contenu panel temps réel (campagnes d'affiliation, annonces admin) invisible en build store — un lien d'achat poussé pendant l'examen ne peut plus apparaître | `affiliate_card.dart`, `announcement_banner.dart` | 9344a9de |

Parcours examinateur VÉRIFIÉ dans le code : lancement → onboarding →
accueil vide (`SimpleHomeScreen._buildActivationEntry`) → bouton
« Mode démo » (1 tap, sans identifiants) OU bloc « Activer les chaînes »
→ « J'ai un code Xtream » (`MacActivationView` → `showXtreamLoginSheet`)
→ champs serveur / identifiant / mot de passe. `GPLAYREVIEW` tapé comme
identifiant court-circuite tout appel réseau et charge la démo embarquée.

## 3. Versions — règle à ne PAS casser

- Le `versionCode` de l'AAB = **numéro de run CI** (`--build-number=${{ github.run_number }}`
  dans `build-android.yml`). Il est monotone : chaque build est acceptable
  par la Play Console sans intervention.
- La prod est en 1349 → ne JAMAIS revenir au `+20` du `pubspec.yaml`
  (rejet « version code déjà utilisé / doit être supérieur »). Le pubspec
  ne pilote que le `versionName` (1.0.1).

## 4. Identifiants — règle de sécurité

- AUCUN identifiant en clair dans le dépôt (vérifié par grep — rien à ce
  jour). Les identifiants de la ligne de test (`googleplay_review`) ne
  vivent QUE dans la Play Console (Contenu de l'application →
  Informations de connexion). Ne les committer nulle part, pas même dans
  un fichier « privé » du dépôt : le dépôt est public.
- Le code `GPLAYREVIEW` n'est PAS un secret (il ne débloque que la démo
  embarquée, accessible par ailleurs d'un tap).

## 5. Produire l'AAB signé (déjà automatisé)

1. Workflow **`build-android.yml`** (déclenché par push sur la branche, ou
   `workflow_dispatch` — note : le bouton n'apparaît que pour les
   workflows présents sur `main`). Il construit l'AAB **signé** avec
   `PLAY_BUILD=true`, applicationId `com.manzilionellm.tvking`, minSdk 24,
   targetSdk = valeur Flutter courante (conforme Play), manifeste sans
   `REQUEST_INSTALL_PACKAGES` ni `READ_MEDIA_*`.
2. Workflow **`publish-phone-aab.yml`** (dispatch, vit sur `main`) avec le
   `run_id` du build → attache `7motion.aab` à la release `phone-test` :
   `https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-test/7motion.aab`
3. Secrets GitHub requis (EXISTANTS — ne pas recréer) :
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`.

## 6. Resoumission — étapes exactes dans la Play Console

1. **Production → Créer une release** (ou modifier la release refusée) →
   téléverser le `7motion.aab` fraîchement publié (versionCode = numéro de
   run, forcément > 1349).
2. **Contenu de l'application → Informations de connexion** : entrée
   « Connexion abonnement (Xtream) » déjà enregistrée — vérifier que le
   mot de passe n'est PAS vide, et que les instructions (anglais)
   mentionnent le code `GPLAYREVIEW` en solution sans serveur :
   voir le texte prêt à coller dans `docs/play-review-access.md`.
3. **Fiche** : les 6 modifications fr-FR en attente peuvent partir dans le
   même envoi (captures = écrans RÉELS de l'app, bouquet démo — jamais un
   simple habillage : c'était un motif de blocage précédent).
4. **Vue d'ensemble de la publication → Envoyer pour examen.**
   Ne PAS faire d'appel de la décision (5–8 jours, et perdu d'avance
   puisque la cause initiale était réelle).

## 7. Checklist avant CHAQUE envoi

- [ ] CI verte sur le commit exact : Quality + Tests + Build Android.
- [ ] AAB construit avec `PLAY_BUILD=true` (visible dans les logs du run).
- [ ] versionCode du run > dernier versionCode Play (prod : 1349).
- [ ] Ligne de test du panel VÉRIFIÉE le jour même :
      `http://<panel>/player_api.php?username=…&password=…` →
      `"auth":1` et `"status":"Active"` ; ≥ 1 an, ≥ 2 connexions,
      sans verrou MAC, sans géoblocage (les examinateurs testent des
      États-Unis).
- [ ] Code `GPLAYREVIEW` testé sur un appareil vierge avec le build exact
      soumis (identifiant `GPLAYREVIEW`, mot de passe quelconque).
- [ ] Aucun prix/lien d'achat visible dans le build (gardes
      `kIsStoreBuild` : pricing, paywall, gate, carte abonnement,
      onboarding, affiliation, annonces).
- [ ] Politique de confidentialité en ligne et cohérente avec la fiche
      (`docs/privacy.html`).
- [ ] Déclaration « Informations de connexion » : identifiant + mot de
      passe remplis + instructions anglaises à jour.

## 8. Risques résiduels de refus (connus, assumés)

1. **Parcours d'activation revendeur toujours présent** en build Play
   (bloc « Activer l'application », numéro de référence). Choix produit
   assumé ; `GPLAYREVIEW` permet à l'examinateur de tout contourner. Zone
   la plus exposée si Google réexamine sous l'angle 3.1.1 (paiements).
   Plan B déjà codé : le drapeau `IOS_STORE_BUILD` retire ce parcours —
   en faire un équivalent Play serait trivial si un refus le cite.
2. **Écran bloquant essai/gel** (`SubscriptionGateScreen`) : reste actif
   en build Play (sans prix ni bouton d'achat). Si l'examinateur laisse
   expirer l'essai de 7 jours pendant l'examen, il verra cet écran ;
   `GPLAYREVIEW`/démo restent accessibles avant expiration.
3. **Fiche** : ne jamais mentionner de chaînes/marques réelles dans les
   captures ou la description (motif de refus n°1 des lecteurs IPTV).
