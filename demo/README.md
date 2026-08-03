# Playlist de démonstration — 7 MOTION

`7motion-demo.m3u` : une vraie playlist M3U, à coller dans l'app comme
n'importe quelle source de client.

## À quoi elle sert

Le mode démo intégré injecte son bouquet **en mémoire** : il ne passe
donc ni par l'analyseur M3U, ni par la base SQLite, ni par la synchro.
Ce fichier, lui, emprunte **exactement le chemin d'un vrai client** —
téléchargement de la liste, analyse, rangement par catégorie, lecture.
C'est ce qu'il faut pour vérifier une chaîne complète sans avoir à
demander son abonnement à quelqu'un.

## Les liens

14 clips, hébergés sur GitHub, **épinglés à un commit précis** : leur
contenu ne peut plus changer, et aucune modification du dépôt ne les
casse.

Pourquoi GitHub et pas ailleurs : c'est le seul hébergeur dont on ait la
**preuve** qu'il répond depuis l'appareil du client — c'est de là qu'il
télécharge l'APK plusieurs fois par jour. Après une journée passée à se
faire refouler par un CDN qui renvoie 403 et par un autre qui exigeait un
TLS que l'app ne négociait pas, on ne choisit plus un hébergeur sur sa
réputation.

Les 14 URL ont été vérifiées une par une : toutes répondent `206 Partial
Content`, donc avec le support du Range — le lecteur peut se déplacer
dans le fichier au lieu de le télécharger en entier.

## Ce que la playlist ne contient pas

Aucune chaîne réelle, aucun logo de diffuseur, aucun lien de fournisseur.
Uniquement des clips fabriqués pour ce projet (voir
`tools/generate_demo_clips.py`) et la vidéo de présentation du client.

Ce n'est pas une précaution de façade : une seule chaîne réelle dans une
capture d'écran suffit à faire refuser la fiche Play Store, et à faire
passer l'app du statut de *lecteur* à celui de *distributeur de contenu*.

## Régénérer

Les clips changent → il faut réépingler le M3U sur le nouveau commit :

```bash
python3 tools/generate_demo_clips.py assets/demo   # refait les clips
git add -A && git commit && git push                # publie
python3 tools/build_demo_m3u.py                     # réépingle les URL
```

## Si tu veux y ajouter des films libres

Les films de la Fondation Blender (Big Buck Bunny, Sintel, Tears of
Steel) sont sous licence Creative Commons et se prêtent bien à une démo.
Ils sont servis en HLS par plusieurs CDN publics.

Deux réserves, apprises à nos dépens : ces hôtes n'ont **pas** été
vérifiés depuis l'appareil du client, et l'un d'eux (le dépôt
d'échantillons de Google) s'est mis à répondre `403` du jour au
lendemain. Si tu les ajoutes, teste-les **avant** de montrer la playlist
à quelqu'un.
