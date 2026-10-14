# Inspection interface — panel admin

Parcours fait en local, le 3 octobre 2026. Le panel tourne avec Vite
(`http://127.0.0.1:5173`). Une API factice écoute sur le port 8787
(`audit/mock-api.mjs`) : aucun mot de passe réel, aucun lien de flux.

Outil : Playwright + Chrome, plus axe-core (règles WCAG 2.1 AA).

- 23 pages × 3 tailles d'écran (1440, 768, 390)
- 643 clics de boutons et de liens
- captures avant / après jointes à la revue

Commandes :

```bash
cd android-app/admin-panel
node audit/mock-api.mjs
npm run dev -- --host 127.0.0.1 --port 5173
# avant correctifs : node audit/crawl.mjs
# après correctifs : node audit/verify.mjs
npx tsc -b --pretty false --noEmit
```

`node audit/verify.mjs` se termine sans échec (16 contrôles PASS).
`tsc -b` se termine sans erreur.

Le site en ligne n'a pas été modifié. Rien n'a été déployé.

---

## Haute — couleurs « succès » et « attention » invisibles

**PROUVÉ, corrigé.**

Fichier : `tailwind.config.cjs` (couleurs, à côté de `ink`).
Les pages utilisent `text-success` et `text-warning` (puce « Actif »,
compteur « En ligne », messages verts). Ces couleurs n'existaient pas
dans le thème Tailwind. Le commentaire de `ReferencesPage.tsx` (ligne 18)
le disait déjà : les badges de cette page seule utilisent une couleur en dur.

Avant, sur `/control-center`, la puce « Actif » :

- couleur calculée `rgb(240, 237, 233)` — la même que le texte normal
- aucune règle CSS `text-success` dans les feuilles de style

Après : `rgb(63, 190, 124)`, règle CSS présente.
Le compteur « En ligne maintenant » passe au même vert.
Contrôle : `PASS puce Actif verte` et `PASS compteur en ligne vert`.

## Haute — tableaux coupés sur téléphone et tablette

**PROUVÉ, corrigé.**

Le cadre du tableau avait `overflow-hidden`. Le tableau était plus large
que l'écran, donc les dernières colonnes étaient coupées, sans défilement.

Mesure avant (largeur tableau > cadre, pas de défilement) :

| Écran | Page | Tableau | Cadre |
|---|---|---|---|
| 390 px | Activations | 546 | 356 |
| 390 px | Clients | 456 | 356 |
| 390 px | Revendeurs | 898 | 356 |
| 390 px | Références | 714 | 356 |
| 390 px | Historique | 418 | 356 |
| 390 px | En ligne | 474 | 356 |
| 768 px | Activations, Revendeurs, Références, En ligne | trop large | 462 |

Fichiers : `ActivationsPage.tsx` ligne 44, `CustomersPage.tsx` ligne 54,
`ResellersPage.tsx` ligne 73, `ReferencesPage.tsx` ligne 98,
`HistoryPage.tsx` ligne 54, `OnlinePage.tsx` ligne 110.
Le cadre est passé à `overflow-x-auto`.

Après, sur Activations en 390 px : le contrôle
`PASS tableau activations défile` (le tableau peut défiler).

## Haute — connexion sans identifiant

**PROUVÉ, corrigé.**

`LoginPage.tsx` : le bouton « Se connecter » n'était bloqué que si le mot
de passe était vide. Un mot de passe seul, identifiant effacé, lançait la
connexion. L'API factice acceptait : la page quittait `/login`
(`emptyIdLeftLogin: true`).

Après : le bouton reste désactivé (`PASS identifiant vide bloque le bouton`).
Un message « Indique un identifiant. » est aussi prévu si le formulaire part
quand même (lignes 49-52).

## Moyenne — inscription revendeur avec un mot de passe d'un caractère

**PROUVÉ, corrigé.**

Même fichier. Le compte « Mon compte » exige 4 caractères
(`i18n.tsx`, clé `account.pwdShort`). L'inscription revendeur, non.
Avant : bouton actif, aucun texte d'aide (`signupShortEnabled: true`).

Après : le formulaire reste sur la connexion et affiche
« Le mot de passe doit faire au moins 4 caractères. »
(`PASS mot de passe court refusé`, `LoginPage.tsx` lignes 53-56).

## Moyenne — le menu téléphone ne se fermait pas au clavier

**PROUVÉ, corrigé.**

`AppLayout.tsx` ligne 32. Le clic sur le fond fermait le menu.
La touche Échap le laissait ouvert : 1 menu visible avant, encore 1 après.

Après : 0 menu visible (`PASS Échap ferme le menu`).

## Moyenne — en-tête Revendeurs plus large que l'écran

**PROUVÉ, corrigé.**

Deux boutons longs (« Copier le lien revendeur » + « Nouveau revendeur »)
dans un en-tête qui ne pouvait pas passer à la ligne.

Avant : largeur utile 390, contenu 460 (tablette : 528 contre 573).
`AppLayout.tsx` : l'en-tête peut passer à la ligne.

Après : 390 = 390 et 528 = 528
(`PASS en-tête revendeurs tient`, `PASS en-tête revendeurs tablette`).

## Moyenne — Centre de contrôle : deux modules marqués « bientôt » alors qu'ils existent

**PROUVÉ, corrigé.**

`ControlCenterPage.tsx` lignes 35 et 39.

- « Thèmes dynamiques » était « Phase 3 », carte non cliquable.
  La page `/theme` existe (nom, couleurs, presets, aperçu).
- « Automatisation » était « Phase 5 » et parlait d'une règle
  « Coupe du Monde → Sport » qui n'existe pas. La page Thème a déjà
  les règles par date (décembre → Noël).

Avant : la carte Thème n'était pas un lien (`isLink: false`).
Après : les deux cartes vont vers `/theme`
(`PASS thème cliquable`, `PASS automatisation cliquable`).

Les cartes « Bannières » (Phase 2) et « A/B Testing » (Phase 5) restent
non cliquables : ces pages n'existent pas. Ce n'est pas un lien mort.

## Moyenne — contraste du petit texte gris

**PROUVÉ, corrigé.**

`ink.tertiary` était `#7E7872`. Sur le fond des cartes, le ratio tombait
à 3,76 (il faut 4,5 pour le texte normal). axe-core comptait 8 écarts
sur la connexion et 17 sur le tableau de bord.

La couleur est passée à `#8E8882` (`tailwind.config.cjs` ligne 32).
Après : 0 écart de contraste sur la connexion et sur le tableau de bord.

Le logo « TF » en rouge `#D63A30` restait sous 4,5. Il est passé au rouge
clair déjà utilisé ailleurs (`#FF5A4A`), dans `LoginPage.tsx` et
`Sidebar.tsx`. Les petits textes `text-accent` (MAC, pastilles) suivent
la même couleur via `styles.css` ligne 34, sans changer le fond des
boutons (texte noir sur le rouge d'origine : ratio 4,51, on n'y touche pas).

Après ce réglage : 0 écart axe `color-contrast` sur les 23 pages,
y compris l'aperçu du thème (les pastilles de l'aperçu utilisaient le
rouge foncé en tout petit).

## Moyenne — champs sans nom pour le lecteur d'écran

**PROUVÉ, corrigé sur les champs signalés.**

axe-core, règle `label` ou `select-name`, gravité critical, avant :

- connexion : étiquettes non reliées aux champs
- compte : 3 mots de passe
- annonces : 2 listes
- accueil : listes « ruban »
- pub : nombre + liste
- tarifs : nombre de jours d'essai
- thème : sélecteur de couleur
- pub et avis : interrupteur sans nom

Chaque étiquette a maintenant un `htmlFor` / `id`, ou un `aria-label`.
Après : `PASS axe … noms — 0` sur ces 7 pages.

## Moyenne — textes anglais et faute sur Activations

**PROUVÉ, corrigé.**

`ActivationsPage.tsx`.

- colonne « Device MAC » → « MAC »
- statut affiché `active` / `expired` → « Actif » / « Expiré »
  (`statusLabel`, ligne 98)
- bouton « Activer un MAC » → « Activer une MAC » (ligne 36)

Contrôle après : la page contient ACTIF, EXPIRÉ, MAC, et plus
« Device MAC ».

## Moyenne — icône du site

**PROUVÉ, corrigé.**

`index.html` ligne 5 demande `/favicon.svg`. Il n'y avait pas de dossier
`public/`. Avant : `curl -sI http://127.0.0.1:5173/favicon.svg` renvoyait
`Content-Type: text/html` (la page HTML à la place de l'icône).

Après : `Content-Type: image/svg+xml` (`PASS favicon svg`).
Fichier ajouté : `public/favicon.svg`.

## Basse — titre de l'onglet

**PROUVÉ, corrigé.**

`index.html` ligne 8. Avant : « App Licensing Platform — Admin ».
Le bandeau du panel dit « The Few ». Après : « The Few — Admin »
(`PASS titre`).

## Basse — flèche « monter » sans effet sur la première ligne

**PROUVÉ, corrigé.**

`HomeManagerPage.tsx` ligne 161. `move()` ne fait rien si la cible est
au-dessus de 0. Le premier clic sur ▲ ne changeait pas la page
(relevé « no-effect »). Le bouton est maintenant désactivé sur la première
ligne, et ▼ sur la dernière. Contrôle : `first up disabled true`.

---

## Ce qui a été vu et n'est pas un bouton mort

Ces clics ne changeaient pas le texte de la page. Ce n'est pas un défaut
d'interface :

- « Forcer la mise à jour », « Tout retirer », « Suppr. », « Restaurer »,
  « Supprimer » un serveur : une boîte de confirmation s'ouvre
  (6 dialogues relevés). Annuler ne change rien. C'est voulu.
- « Donner 7 jours… » ouvre une question (prompt), pas un bouton mort.
- Les durées déjà sélectionnées sur « Activer » ne changent pas le texte
  si on reclique la valeur active.
- « Télécharger une sauvegarde » : le texte de la page ne change pas parce
  que l'action est un téléchargement de fichier. **NON PROUVÉ** comme panne :
  le test ne surveillait pas le fichier téléchargé.
- Les cases de droits revendeur : l'API factice ne mémorisait pas la case.
  **NON PROUVÉ** comme panne d'écran.

Aucun lien interne vers une route inconnue. La console n'a que deux
avertissements React Router sur une future version. Pas d'erreur JavaScript.

---

## Non corrigé — à décider ailleurs

### Marque « The Few » alors que le site public dit « Zuno »

**À VÉRIFIER SUR LE VRAI SITE.**

Le bandeau, la connexion et les textes du panel disent « The Few »
(`i18n.tsx` ligne 27, logo « TF »). Le site vitrine du dépôt dit « Zuno ».
Ce n'est pas un renommage : un autre travail refait déjà l'interface.
Le titre d'onglet a seulement été aligné sur le nom déjà affiché dans le panel.

### Deux cartes du tableau de bord vers la même page

**PROUVÉ, non corrigé.**

`DashboardPage.tsx` lignes 122 et 127 : « Activer un client » et
« Activer / pousser une source » vont toutes les deux vers `/activate`.
Séparer l'activation et le lien M3U est le travail de l'autre branche.
Les deux cartes répondent au clic (ce ne sont pas des boutons morts).

### Aperçu du thème : noms de chaînes

**PROUVÉ à l'écran, non corrigé.**

`ThemePage.tsx`, maquette du téléphone : des noms du type « FRANCE SPORT »,
« DAZN », « AMAZON PRIME » sont écrits en dur dans l'aperçu. Ce n'est pas
un lien de flux. C'est du texte de démonstration. Laissé tel quel pour ne
pas refaire la maquette.

### Page « Pousser une playlist » non branchée au menu

**PROUVÉ dans le code, pas un lien mort à l'écran.**

`PushSourcePage.tsx` existe. `App.tsx` n'a pas de route pour elle.
`/playlists` redirige vers `/activate`. Le menu ne propose pas cette page.
C'est la fusion déjà faite. Pas de bouton visible qui ne mène nulle part.

---

## À VÉRIFIER SUR LE VRAI SITE

Tout ce qui précède est prouvé sur le panel local, avec des données
factices. Le site `https://tvking-admin.pages.dev` n'a pas été modifié
et n'a pas été parcouru une fois connecté (pas d'identifiant réel utilisé).

À contrôler après un déploiement décidé par Lionel :

- le vert des statuts « Actif » et du compteur « En ligne »
- le défilement horizontal des tableaux sur un téléphone
- la connexion qui refuse un identifiant vide
- le menu qui se ferme avec Échap
- l'icône d'onglet (plus une page HTML)
- le Centre de contrôle : Thème et Automatisation cliquables
