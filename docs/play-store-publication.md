# Publier The Few sur le Play Store (et ailleurs) — guide + protections anti-ban

> ⚠️ **Privé (édition 18+) ne peut PAS aller sur le Play Store** : Google interdit
> le contenu adulte/pornographique (règle « Contenu sexuel explicite »). Privé
> reste en **sideload** (lien `prive-latest`) ou sur un store adulte. Ce guide
> ne concerne donc QUE **The Few** (lecteur neutre, sans contenu pré-rempli).

---

## 1. Pourquoi The Few est publiable (et défendable)

Le motif n°1 de bannissement des apps « IPTV », c'est de **fournir** l'accès à
des flux/chaînes (contenu piraté). The Few ne fournit **rien** :

- ✅ Aucune playlist ni URL de flux en dur (vérifié dans le code).
- ✅ L'utilisateur **apporte sa propre source** (M3U / Xtream / code d'activation).
- ✅ C'est un **lecteur multimédia générique**, comme VLC ou TiviMate.

C'est exactement le modèle « BYO playlist » qui est toléré. Il faut que le
**listing** et les **métadonnées** reflètent ça (voir §4).

---

## 2. Pré-requis (côté toi)

1. **Compte Google Play Console** : 25 $ une fois. Vérification d'identité
   obligatoire (compte perso : ~48 h ; compte société : D-U-N-S requis).
2. **Politique de confidentialité en ligne** : déjà servie → `https://7motion.app/privacy`.
3. **Page CGU/Terms en ligne** (recommandé) : à publier sur `…/terms` (le
   contenu existe dans `legal/cgu.md`).
4. **L'AAB signé** : déjà produit par le CI à chaque build →
   `7motion.aab` sur la release `latest`. (Play exige un .aab, pas un .apk.)

---

## 3. Procédure pas-à-pas (Play Console)

1. **Créer l'application** : nom « The Few », langue par défaut, type *App*, *Gratuite*.
2. **Configuration du tableau de bord** (tout est obligatoire avant prod) :
   - *Politique de confidentialité* → `https://7motion.app/privacy`
   - *Accès à l'application* → fournir un **compte/code de démonstration**
     (un code d'activation MAC + une source de test) pour que le relecteur
     puisse voir l'app fonctionner. **Sans ça = rejet quasi systématique.**
   - *Publicités* → déclarer si l'app contient des pubs.
   - *Classification du contenu* → remplir le questionnaire (sélectionner
     *Aucun contenu sexuel/violent* ; The Few est un lecteur).
   - *Public cible* → 18+ (évite les obligations « familles »).
   - *Data safety* → voir §5.
   - *App content / declarations* → déclarer le **service au premier plan**
     (l'enregistrement utilise un foreground service) et sa justification.
3. **App signing** : activer **Play App Signing** (Google gère la clé).
4. **Créer une release** : commencer par **Tests internes** (upload du `7motion.aab`).
   Tester avec quelques comptes, puis passer en **Test fermé** → **ouvert** →
   **Production**.
5. **Soumettre** : la 1re revue prend de quelques heures à ~7 jours.

---

## 4. Texte de listing « anti-ban » (à copier)

**Titre** : `The Few — Lecteur multimédia`

**Description courte** :
> Lecteur multimédia pour VOS playlists et VOTRE abonnement. Aucun contenu fourni.

**Description longue (extrait)** :
> The Few est un **lecteur multimédia** (M3U / Xtream Codes) qui lit **vos
> propres sources**. L'application **ne fournit, n'héberge et ne diffuse aucun
> contenu** : vous devez disposer de votre propre playlist ou abonnement légal.
> Fonctions : lecture HLS/TS/HEVC, EPG, favoris, enregistrement local, Cast,
> mode audio, reprise de lecture.

**À NE PAS faire dans le listing (déclencheurs de ban)** :
- ❌ Mots « gratuit films/séries/chaînes », « free movies », « live TV gratuite ».
- ❌ Logos / marques de chaînes (TF1, beIN, Canal+, Netflix…).
- ❌ Captures montrant des chaînes payantes ou des marques.
- ❌ Promesses de contenu (« +10 000 chaînes »).
- ✅ Captures **neutres** : écran d'accueil vide, écran « ajoute ta source », réglages.

---

## 5. Réponses « Data safety » (questionnaire Play)

- **Données collectées** : identifiant d'appareil (ANDROID_ID) pour l'activation ;
  pas de nom/email obligatoire.
- **Chiffrement en transit** : oui.
- **Suppression des données** : fournir un moyen (page/contact) — à mentionner
  sur `/privacy`.
- **Partage avec des tiers** : non (sauf le serveur d'activation, qui est le tien).

---

## 6. Où publier DÈS AUJOURD'HUI

| Plateforme | The Few | Privé (18+) | Notes |
|---|---|---|---|
| **Sideload / Cloudflare** (déjà en place) | ✅ | ✅ | `latest/7motion.apk`, `prive-latest/prive.apk` |
| **Amazon Appstore** | ✅ | ❌ | Accepte les lecteurs IPTV, public Fire TV. Gratuit. |
| **Samsung Galaxy Store** | ✅ | ❌ | Possible pour un lecteur. |
| **Aptoide / APKPure** | ✅ | ⚠️ | Stores ouverts, moins stricts (mais moins de confiance). |
| **Huawei AppGallery** | ✅ | ❌ | Marché hors-Google. |
| **Google Play** | ⚠️ (possible si listing neutre) | ❌ interdit | Le plus gros, le plus strict. |

**Conseil** : commence par **Amazon Appstore** (rapide, tolérant, et tes clients
Fire TV sont déjà là) + garde le **sideload**. Tente **Play Store** en parallèle
avec le listing neutre ci-dessus.

---

## 7. Rappels de protection (résumé)

- ✅ Zéro flux/playlist en dur (maintenir cette règle — déjà dans AGENTS.md).
- ✅ Disclaimer « lecteur, contenu apporté par l'utilisateur » visible.
- ✅ `/privacy` en ligne ; ajouter `/terms`.
- ✅ Accès testeur (code démo) fourni à Google.
- ✅ Privé jamais sur les stores mainstream.
- ⚠️ Aucune garantie absolue : l'IPTV est une catégorie surveillée. Le listing
  neutre + le modèle « BYO playlist » sont la meilleure défense.
