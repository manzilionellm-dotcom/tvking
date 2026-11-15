# Pauses du lecteur : les mesurer, et un coussin facultatif

## Le problème vu le 15/11

Sur TF1, le son s'arrêtait puis repartait : 4 pauses de 2 à 5 s en 80 s (environ
20 % du temps). Le journal montrait que le décodage était correct, mais ne disait
**pas pourquoi** le lecteur attendait. Deux familles de causes donnent la même
pause :

- **le serveur (ou le réseau) n'envoie plus rien** : le lecteur n'a plus de quoi jouer ;
- **l'appareil ne suit pas** : les données arrivent, mais le décodage ou l'affichage prend du retard.

Le journal ne les distinguait pas, et il était noyé : à chaque changement du
compteur « Android en compte N », le rapport de son complet (12 lignes) était
réécrit.

## Ce que ça change

### 1. Une ligne par pause, étiquette `LECTURE`

À chaque pause terminée (au moins 0,7 s ; jamais à l'ouverture d'une chaîne, ni
juste après un saut dans un film), une ligne :

```
[LECTURE] [TF1] Pause n°2 : 3,1 s. Réserve au début : 0,4 s. Silence du serveur
pendant la pause : 2,9 s. Reçu pendant la pause : 3 Ko. Images perdues : 0.
Réseau : Wi-Fi (-58 dBm). Bilan : 2 pauses, 5,8 s depuis l'ouverture (7 %).
→ Le serveur n'envoyait rien pendant la pause : le flux ou le réseau, pas l'appli.
```

Comment lire la dernière phrase :

| Phrase | Ce que la mesure a vu | Piste |
|---|---|---|
| « Le serveur n'envoyait rien… » | aucun octet pendant au moins 60 % de la pause (et 1 s) | fournisseur ou réseau |
| « … images ont été perdues : l'appareil ne suit pas » | des octets arrivaient et le décodeur a perdu des images | appareil |
| « Des données arrivaient pendant toute la pause (N kbit/s) » | pas de silence, pas d'image perdue | débit trop faible, ou appareil lent |
| « Le serveur envoyait par à-coups… » | silences courts mais répétés | serveur ou réseau instable |

Ces phrases sont des **pistes tirées de mesures**, pas des preuves : « le serveur
n'envoyait rien » veut dire que le lecteur n'a rien reçu du réseau, ce qui peut
aussi venir du Wi-Fi de la box.

Rien dans la ligne ne peut contenir d'adresse : elle ne reprend que des durées,
des octets, un compteur d'images et le type de réseau.

### 2. Le rapport de son n'est plus répété

Le premier rapport de chaque ouverture (« Cycle : zap n°N ») est écrit en entier ;
les suivants de la même ouverture n'écrivent **que les lignes qui ont changé**.
La ligne « Annonces : Android en compte N » (le changement lui-même) part
toujours. La fiche de l'écran Diagnostic reste complète.

### 3. Réglage « Coussin anti-coupure » (Réglages → En plus), coupé par défaut

Après une coupure du direct, le lecteur repart dès 2 s de réserve (réglage
d'origine, inchangé depuis septembre). Allumé, il attend **5 s**. Effet attendu :
moins de coupures, mais chacune plus longue. **Non vérifié sur une vraie box** :
c'est pour essayer, avec les lignes `LECTURE` comme preuve.

Garde-fous (une reprise allongée avait laissé des chaînes bloquées sur le logo en
septembre, v99–v101) :

- il n'**ajoute** qu'une attente : jamais de reprise plus tôt que Media3 ;
- il ne joue qu'après une **coupure** (pas au démarrage, pas après un saut) ;
- il respecte la fenêtre du direct (jamais plus que la moitié du retard visé) ;
- au bout de 10 s d'attente il laisse repartir quand même.

Coupé, la décision est celle de Media3, mot pour mot (le contrôle de chargement
est construit avec les mêmes valeurs qu'avant : 5 s / 45 s / démarrage 1 s / reprise 2 s).

## Ce qui est vérifié, ce qui ne l'est pas

Vérifié automatiquement : suivi des pauses et phrases (17 tests Kotlin sans Android),
politique du coussin (y compris la fenêtre du direct et la sortie au bout de 10 s),
suppression des répétitions du rapport, réglage mémorisé et envoyé **avant** la
première adresse (tests Flutter).

**Non vérifié** : le code qui touche Media3 (écoute des octets reçus, contrôle de
chargement) n'a pas pu être compilé ni lancé sur une vraie box depuis la session ;
il est compilé par les tests Android de GitHub. L'effet réel du coussin sur un flux
qui coupe, et la justesse des phrases de conclusion sur un vrai flux, restent à
constater sur une box.
