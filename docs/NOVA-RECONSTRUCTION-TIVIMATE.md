# NOVA+ — Plan de reconstruction (référence : TiViMate, TV uniquement)

> Objectif : reconstruire **l'expérience TiViMate** (qualité, parcours, fluidité) pour
> téléviseur uniquement, avec une **identité NOVA+ propre** (aucun asset/logo/marque copié).
> Ce doc décrit **chaque écran** observé chez TiViMate + l'ordre de construction.
> Sources : voir bas de page. Date : 2026-06-06.

---

## A. Inventaire des écrans & parcours TiViMate (à reproduire)

### 1. Premier lancement — Ajout de playlist
- Écran « Ajouter une playlist » → choix **Xtream Codes** (URL serveur + identifiant + mot de
  passe) **ou** **M3U** (URL de playlist). *(Xtream recommandé : EPG + catch-up + séries auto.)*
- Chargement de la playlist → **Suivant**.
- (Option) Ajout d'une **source EPG XMLTV** (URL) si non fournie par Xtream.
- ➜ NOVA+ : ce parcours sera adapté à **l'auth par MAC / code d'activation** côté backend
  (à confirmer), l'URL Xtream/M3U pouvant être injectée par le panel.

### 2. Écran principal (TV en cours + overlays)
- **Lecture plein écran** de la chaîne courante en fond.
- **OK** → barre d'info : nom de l'abonnement en haut, **logo + n° de chaîne**, **now/next**
  (programme courant + suivant avec horaires/progression).
- **Haut / Bas** → zapping chaîne précédente / suivante.
- **Gauche / Droite** (ou OK) → **liste des chaînes en surimpression** (la vidéo continue).
- **Appui long OK** → menu contextuel (favori, infos, PiP, enregistrer).

### 3. Liste de chaînes (overlay) + rail des groupes
- **Panneau gauche = groupes/catégories** (issus de la playlist) ; masquables/réordonnables.
- **Colonne chaînes** : logo (1:1), n°, nom, **now/next** ; chaîne en cours surlignée.
- Navigation D-pad ; OK = bascule plein écran sur la chaîne.

### 4. Guide TV (EPG — grille)
- **Lignes = chaînes**, **colonnes = temps** (demi-heures) ; programme en cours mis en évidence.
- **Haut/Bas** = autres chaînes ; **Droite** = programmes à venir ; **Gauche** = retour/passé.
- **OK sur un programme** → détails + **Replay (catch-up)** si dispo + **Planifier enregistrement**.
- Réglages EPG : nb de jours, taille de la grille, priorité des logos, descriptions.

### 5. Favoris
- **Appui long sur une chaîne → Ajouter aux favoris** ; **plusieurs groupes de favoris**
  (Sport, News, Films…). Groupe « Favoris » épinglé en tête du rail gauche.

### 6. Recherche
- Recherche chaînes + programmes ; **saisie minimale** (clavier D-pad), **voix** si possible.

### 7. Catch-up / Replay
- Depuis l'EPG (si provider compatible) : revoir les X derniers jours, barre de progression,
  ±10 s, reprise.

### 8. Enregistrement (nDVR) — premium
- Planifié depuis l'EPG ; enregistrements vers stockage local/externe ; écran « Enregistrements ».

### 9. Multi-view — premium
- Jusqu'à **9 chaînes** simultanées (mosaïque), focus = chaîne active (audio).

### 10. Picture-in-Picture
- Mini-lecteur flottant pendant la navigation EPG/réglages.

### 11. Réglages
- **Playlists** (gérer les groupes, ré-ordonner, masquer), **EPG**, **Apparence** (thème,
  taille, aperçu zone de sécurité/overscan), **Lecteur** (décodeur, buffer, ratio),
  **Contrôle parental**, **Multi-view**, **Enregistrement**, **À propos**.

---

## B. Mapping écrans → routes NOVA+ (front Next.js existant, repurposé)
| Écran TiViMate | Route NOVA+ | Réutilise l'existant |
|---|---|---|
| Premier lancement / playlist | `/setup` (ou activation MAC) | nouveau |
| Écran principal + overlays | `/watch` (lecteur plein écran + overlays) | adapte `watch/[slug]` |
| Liste chaînes + groupes | overlay global + rail gauche | adapte `Sidebar` |
| Guide TV (EPG) | `/guide` | nouveau (grille) |
| Favoris | `/favorites` | adapte `list/` |
| Recherche | `/search` | existe |
| Catch-up / Replay | dans `/guide` + `/watch` | nouveau |
| Enregistrements | `/recordings` | nouveau |
| Multi-view | `/multiview` | nouveau |
| Réglages | `/settings` | adapte `reglages/` |

> Le thème actuel « Sport/Formation royal » est **remplacé** par l'identité NOVA+ et la
> palette IPTV (cf. `RESEARCH-IPTV-NOVA.md` §4), calée sur le logo/couleur dès réception.

---

## C. Ordre de construction proposé (jalons)
1. **Shell + thème NOVA+** : layout TV, rail gauche groupes, palette, focus D-pad, safe-area.
2. **Modèle de données IPTV** : chaînes, groupes, programmes EPG, favoris, état live
   (d'abord **données démo**, puis branchement Xtream/M3U).
3. **Écran principal + lecteur** : plein écran, barre d'info now/next, zapping Haut/Bas,
   overlay liste chaînes.
4. **Guide TV (EPG)** : grille temps × chaînes, navigation, détails programme.
5. **Favoris + Recherche**.
6. **Branchement données réelles** : Xtream Codes / M3U + EPG XMLTV (+ auth MAC/panel).
7. **Premium** : catch-up, enregistrement, multi-view, PiP.
8. **Polish + recette** : perf zapping, contraste, identité, build APK (wrapper WebView).

---

## État de la reconstruction (V1)
Implémenté sur le front Next.js (M3U + XMLTV direct, périmètre « cœur live ») :
- [x] Modèle de données IPTV + **parseur M3U** (`tvg-id/logo/group`) + **parseur XMLTV** + jointure now/next.
- [x] Chargement serveur (fetch + parse + cache TTL) ; source configurable (M3U/Xtream + XMLTV) via Réglages (cookies) ou env.
- [x] **Accueil** : rail des groupes + grille de chaînes, **Favoris** + **Récemment vues** (localStorage).
- [x] **Lecteur** plein écran (HLS via hls.js + fallbacks), barre **now/next**, **zapping** ▲▼, **liste de chaînes** en surimpression, favori (F), retour.
- [x] **Guide TV** (grille EPG temps × chaînes, programme en cours surligné).
- [x] **Recherche** de chaînes, **Favoris**, **Réglages** (source + taille texte/overscan).
- [ ] À suivre (jalons ultérieurs) : catch-up/replay, enregistrement, multi-view, PiP, auth par MAC/panel, build APK (wrapper WebView) + workflow.

Vérifié : `npm run build` + `npm run lint` OK ; test bout-en-bout offline (source `data:`) →
parsing 3 chaînes/2 groupes, EPG joint, APIs `channels`/`nownext` et pages Accueil/Guide/Lecteur/Réglages rendues côté serveur.

## Sources
- [tivimateiptvplayer.net — Mastering TiViMate](https://tivimateiptvplayer.net/mastering-tivimate/)
- [tivimate.co.com — Features](https://tivimate.co.com/app/features/)
- [iptv-help.com — TiViMate EPG](https://iptv-help.com/iptv-help-me/tivimate/tivimate-epg/)
- [iptv.us.com — TiViMate setup guide](https://iptv.us.com/blog/tivimate-setup-guide-complete)
- [optimedia.tv — TiViMate setup Firestick/Android](https://optimedia.tv/blog/tivimate-setup-guide-firestick-android)
- [husham.com — M3U & Xtream Codes 2025](https://www.husham.com/how-to-use-m3u-xtream-codes-in-iptv-apps-2025-guide/)
