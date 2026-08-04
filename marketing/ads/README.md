# Visuels — campagne Google Ads App

Trois formats, ceux que Google diffuse le plus :

| Fichier | Dimensions | Où il apparaît |
|---|---|---|
| `ads-paysage-1200x628.png` | 1200 × 628 | le plus servi — dans les apps, sur le Réseau Display |
| `ads-carre-1200x1200.png` | 1200 × 1200 | fil YouTube, Discover |
| `ads-portrait-1200x1500.png` | 1200 × 1500 | plein écran mobile |

Minimums acceptés par Google : 600×314, 300×300, 480×600. JPG ou PNG,
5 Mo maximum, jusqu'à 20 images par campagne.

## Deux partis pris

**Une vraie capture de l'application au centre.** Une campagne App qui
ne montre pas l'app promet quelque chose que le clic ne tient pas.
Google le sanctionne par un score d'efficacité « Médiocre » — qui coûte
plus cher que le visuel lui-même.

**Le texte dit exactement ce que dit la fiche** : « VOTRE M3U. VOTRE
XTREAM. » et, en bas, « Lecteur — aucune chaîne fournie ». Promettre
des chaînes sur l'annonce, c'est acheter des installations qui
désinstallent en trois minutes — et se contredire devant l'examinateur
qui a validé la fiche.

Aucun nom de chaîne réelle, aucun logo de diffuseur : la capture est
prise en mode démo.

## Régénérer

```bash
python3 tools/generate_ad_images.py marketing/ads
```

La capture source est `marketing/play/screenshots/01-accueil-categories.png`.
Change-la, ou change les textes dans le script, et relance.

## Les vidéos

Google les veut **hébergées sur YouTube**, en 16:9, 9:16 et 1:1,
10 secondes minimum. Elles ne sont pas encore faites.

---

## Les vidéos

| Fichier | Format | Durée |
|---|---|---|
| `video-16x9-1920x1080.mp4` | paysage 16:9 | 15 s |
| `video-9x16-1080x1920.mp4` | portrait 9:16 | 15 s |
| `video-1x1-1080x1080.mp4` | carré 1:1 | 15 s |

H.264 + AAC. Le minimum exigé par Google est 10 secondes.

### Elles doivent passer par YouTube

Google Ads n'accepte **pas** de fichier vidéo importé directement dans
une campagne App : il ne prend qu'une URL YouTube. Il faut donc les
mettre en ligne sur la chaîne YouTube du compte, en **non répertoriée**
(unlisted) — elles n'apparaissent alors ni dans la chaîne, ni dans les
recherches, mais Google Ads sait les diffuser.

### Pourquoi elles comptent

Sans vidéo, l'inventaire YouTube est **fermé** à la campagne. Google ne
diffuse plus que sur une partie de son réseau, la concurrence se
concentre sur ce qui reste, et le coût par installation monte. Le score
« Médiocre » n'est pas une amende : c'est un rendement en moins pour le
même budget.

### Régénérer

```bash
python3 tools/generate_ad_videos.py marketing/ads
```
