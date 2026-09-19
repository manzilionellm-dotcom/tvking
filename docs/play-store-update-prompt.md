# Prompt — Claude dans le navigateur : mettre à jour 7 MOTION sur le Play Store

> À coller tel quel dans Claude (extension Chrome), connecté à la Google Play
> Console de Lionel. Les numéros ci-dessous sont ceux de l'AAB publié par
> `publish-play-aab.yml` : ils changent à chaque publication, et se lisent
> dans la release GitHub `play-aab` (notes de la release). Ne pas réutiliser
> ce prompt avec des numéros périmés.

---

Tu es l'assistant de Lionel, propriétaire de 7 MOTION. Ta mission : publier la mise à jour de l'app Android **7 MOTION** sur le Google Play Store, depuis la Play Console, en suivant les phases ci-dessous dans l'ordre.

## Règles absolues

1. **Tu n'inventes rien.** Toutes les valeurs sont ci-dessous. Une page demande autre chose → tu t'arrêtes et tu me demandes.
2. **Tu me passes la main** pour tout paiement, vérification d'identité, code à deux facteurs, et pour toute déclaration légale que tu ne peux pas vérifier toi-même (voir phase 4).
3. **Tu ne cliques pas « Envoyer pour examen » / « Lancer le déploiement »** sans ma confirmation explicite, écrite, à ce moment-là.
4. Après chaque phase, une ligne : fait / reste. En cas d'erreur, tu cites le message exact de la page.

## Valeurs fixes (copie exacte)

| Champ | Valeur |
|---|---|
| Application | 7 MOTION — package `com.manzilionellm.tvking` |
| Fichier à déposer | `7motion.aab` — https://github.com/manzilionellm-dotcom/tvking/releases/download/play-aab/7motion.aab (lien court : https://app.7themotion.com/phone-aab) |
| versionCode attendu | **{VERSION_CODE}** |
| versionName | **{VERSION_NAME}** |
| SHA-256 du fichier | `{SHA256}` |
| Numéro maison (support) | {BUILD_LABEL} |
| Piste | Production |
| Déploiement | progressif, **20 %** au départ |

**Notes de version (fr-FR, 500 car. max) :**

```
• Son Dolby / DTS envoyé tel quel à votre barre de son ou ampli (HDMI, USB)
• Collage instantané d'un code M3U ou Xtream pour ajouter une liste
• Assistance à distance : prise en main par le support, écran en direct
• Corrections et fluidité
```

**Notes de version (en-US) :**

```
• Dolby / DTS audio passed through untouched to your soundbar or amplifier (HDMI, USB)
• Paste an M3U or Xtream code to add a playlist instantly
• Remote assistance: support can take over, live screen
• Fixes and smoother playback
```

## Phase 1 — Télécharger le fichier

1. Ouvre https://app.7themotion.com/phone-aab : le fichier `7motion.aab` se télécharge (≈ 130 Mo).
2. Tu ne peux pas vérifier le SHA-256 toi-même : c'est la Play Console qui affichera le versionCode après l'import ; il DOIT être **{VERSION_CODE}**. Si un autre numéro s'affiche, arrête-toi et dis-le-moi.

## Phase 2 — La release

1. https://play.google.com/console → application **7 MOTION** → *Tester et publier* → **Production** → onglet *Versions*.
2. S'il existe déjà une **release brouillon** (bouton « Créer une version » grisé) : ouvre-la avec *Modifier la version*. Sinon, *Créer une version*.
3. Si le brouillon contient un ancien bundle (versionCode inférieur à {VERSION_CODE}) : supprime-le de la release avant d'importer le nouveau.
4. Zone *App bundles* → **Importer** → dépose `7motion.aab`.
5. Attends la fin de l'import. Vérifie dans la ligne du bundle : **versionCode {VERSION_CODE}**, versionName {VERSION_NAME}. Sinon → stop, message exact.

## Phase 3 — Notes de version

1. *Nom de la version* : laisse la valeur proposée (elle reprend le versionName).
2. *Notes de version* : colle le texte fr-FR dans `<fr-FR>`, le texte en-US dans `<en-US>`. Ne coche aucune autre langue.
3. **Suivant**.

## Phase 4 — Les déclarations, si la console en demande

La console peut bloquer avec une erreur rouge en haut de la release (« Vous devez nous indiquer si… »). Pour chacune :

- **Autorisations de services de premier plan** — ce build ne demande **plus** `FOREGROUND_SERVICE_MEDIA_PROJECTION` (retirée de l'AAB le 19/09/2026). Il ne reste que **Lecture de contenus multimédias** (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`), déjà déclarée. Si la console redemande une déclaration pour la **projection d'écran**, c'est que le mauvais fichier a été importé : stop, dis-le-moi.
- **Alarmes exactes** — non demandée par ce build (`USE_EXACT_ALARM` retirée ; `SCHEDULE_EXACT_ALARM` est accordée par l'utilisateur). Si elle est redemandée : stop, dis-le-moi.
- **Photos et vidéos** — non demandée par ce build. Idem.
- **Sécurité des données** — déjà remplie ; ne la modifie pas sans me demander.

Tu ne coches **aucune** case de déclaration à ma place : c'est une attestation légale à Google. Tu me décris la case et tu attends ma réponse.

## Phase 5 — Vérifier et déployer

1. **Enregistrer**, puis **Suivant** → page *Prévisualiser et confirmer*.
2. Lis les avertissements. Un avertissement jaune n'empêche pas de publier ; une erreur rouge, si → copie-la-moi.
3. Choisis **Déploiement progressif : 20 %**.
4. **Arrête-toi** et écris-moi : « Prêt à déployer {VERSION_CODE} ({VERSION_NAME}) à 20 % : confirme ».
5. Seulement après mon « confirme » écrit : **Lancer le déploiement** (ou « Envoyer pour examen » si la console le propose à la place).

## Phase 6 — Rapport

Écris-moi : le versionCode et le versionName affichés par la console, l'état de la release (en examen / en cours de déploiement / erreur), le pourcentage, et tout ce que tu n'as pas pu faire.

## Après la publication (pour moi, pas pour toi)

- Sous 24–48 h, revenir sur la Play Console → *Qualité* → *Android Vitals* : si aucun nouveau crash sur ce versionCode, passer le déploiement de 20 % à 100 %.
- Le numéro maison {BUILD_LABEL} est celui que le panel affiche dans la fiche de chaque téléphone : « dernière version » quand le client a mis à jour.
