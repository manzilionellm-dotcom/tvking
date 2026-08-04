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
