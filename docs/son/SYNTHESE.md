# Synthèse — un seul APK de test pour le son

Branche `claude/son-tout-en-un`, partie de `claude/zuno-mesures-audio` (commit `474969c2`).

Douze angles sont dans le même code. Deux branches n'y sont pas, parce qu'elles doublaient un bouton :

- **#77** (`claude/son-1-mode-appel`) n'est pas fusionnée. Elle pose la même clé `zuno.audio.mode.normal` que **#79** (`claude/son-01-mode-audio`). On garde **#79** : elle lit aussi le haut-parleur d'appel, elle ne coupe pas un vrai appel, et elle a le banc `mode_telephone.py`.
- **#84** (`claude/son-2-attributs`) n'est pas fusionnée. C'est le doublon de **#75** (`claude/son-02-attributs`). Il reste **un seul** bouton d'attributs (coupé, film, musique, parole, défaut Media3).

Le son par défaut ne change pas. Chaque interrupteur nouveau est **coupé** si la préférence est absente. Rien n'est publié : pas de release `zuno-tv`, pas de `phone-latest`, pas de Worker, pas le 4K Player.

Le bouton **Rapport son complet** écrit un seul texte à copier. La section **Angles** y met, quand la fiche les a : mode, attributs, chemin (la ligne Chemin reste dans Système, elle n'est pas recopiée une seconde fois), effets, tampon, format, phase, flux, état global (Sources), forme, écho, chute.

Personne n'a écouté la box ni le téléphone ici. Les pourcentages viennent des rapports de chaque angle. Ils ne s'additionnent pas.

## Classement des causes probables

Le symptôme visé : son « vieille radio », « dans un trou », « comme quand on t'appelle », parfois « deux sons », sur la box et sur le téléphone, alors qu'une autre application peut sonner mieux. Les sondes déjà lues sur des chaînes parlées sont à 0,9–3,6 % d'énergie au-dessus de 4 kHz.

| Rang | Idée | Confiance donnée par le rapport | Ce qui la ferait tomber sur l'appareil |
| --- | --- | --- | --- |
| 1 | Le PCM décodé est une parole normale. Le mauvais son est **après** la sonde (AudioTrack, Android, haut-parleur, TV). | Laboratoire : **45 %** | Forme « téléphone » aux quatre sondes (grave et aigu coupés ensemble). |
| 2 | Le 0,9–3,6 % est juste de la parole. La sonde au-dessus de 4 kHz ne peut pas dire « radio ». | Flux : **40 %**. Le banc voix est déjà à 0,4–0,9 % sans filtre. | Une chaîne large (foule, musique) reste basse au-dessus de 4 kHz, ou la signalisation montre un débit très bas. |
| 3 | Le fournisseur ne sert pas le même flux (User-Agent façon VLC, commun aux deux apps). | mpv : **45 %** comme idée, **pas vérifié** sur un serveur. | Une autre app et Zuno ont la même signalisation et le même débit sur la même chaîne. |
| 4 | Le PCM a déjà la forme téléphone (grave et aigu coupés). | Laboratoire : **40 %**. En concurrence avec le rang 1 : les deux ne sont pas vrais en même temps. | Grave/milieu au-dessus de 0,14. |
| 5 | Android est resté en mode communication, haut-parleur d'appel ou Bluetooth d'appel. | Mode : **40 %**. Effets : **20 %** pour le même mécanisme. | La ligne Chemin dit déjà mode normal, haut-parleur d'appel coupé, Bluetooth appel coupé. Alors le rapport mode descend vers **10 %**. |
| 6 | Un traitement de l'appareil après l'AudioTrack (dynamique, virtualiseur, Dolby, type « film »). | Effets : **35 %**. Références (type de contenu) : **35 %**. Attributs : le contenu « film » peut brancher ce traitement ; ce n'est pas prouvé comme cause actuelle. | Chaîne, témoin et une autre app sonnent pareil avec Dolby coupé, et l'essai « contenu inconnu » ne change rien. |
| 7 | Deux copies, un peigne, ou un désaccord dans une seule piste (« trou », « guerre »). Invisible pour le pourcentage au-dessus de 4 kHz. | Tampon : **35 %**. Flux : **30 %**. Laboratoire (écho 20–40 ms) : **20 %**. | Écho sous 18, corrélation proche de +1, et pas de saut d'horloge. |
| 8 | Les voies gauche et droite s'opposent : la voix au centre s'annule. | Phase : **80 %** que ce mécanisme fait le trou **si** la corrélation est ≤ −0,70. Ce n'est **pas** 80 % que France 24 soit dans ce cas : la fiche ne l'a pas encore mesuré. | Corrélation proche de +1. |
| 9 | OpenSL ES rend **7 Motion** moins bon qu'AudioTrack. | mpv : **40 %** pour le téléphone, **15 %** comme cause commune. Mode : **8 %** comme cause commune. | La box (elle n'utilise pas mpv) a le même défaut. |
| 10 | Rééchantillonnage Android (48 kHz vers 44,1 ou autre). | Tampon : **20 %** (monte à 25 % si le mélangeur est à 8–16 kHz, tombe vers 5 % si les deux sont à 48 kHz). | Piste et mélangeur à la même fréquence. |
| 11 | Trous de tampon (underruns) comme son « radio » continu. | Tampon : **15 %**. | Compteurs d'underrun à 0 pendant que le son est mauvais. |
| 12 | Un étage Zuno (Sonic, voix claire, tampon agrandi) filtre au repos. | Chaîne Media3 : **85 %** que **aucun** étage n'est actif quand Spectre, voix claire et saut de silence sont coupés et la vitesse est 1. Donc **faible** comme cause du défaut actuel. | L'essai « Chaîne Media3 » sonne clairement mieux, à chaîne égale. |
| 13 | Deux lecteurs Zuno se chevauchent encore. | État global : **40 %** pour une courte fenêtre au zap. Déjà écarté à l'oreille dans un essai précédent. L'aperçu qui survit au Home est à **85 %** comme fait de code, pas comme cause du son d'une chaîne déjà en plein écran. | Après un retour stable : une seule source en son, un seul AudioTrack. |

Déjà écarté par les mesures d'avant, et non rejoué comme cause : le décodeur de la box jugé aussi mauvais que FFmpeg, le volume du lecteur baissé (déjà à 1,0, focus tenu par Zuno), un passe-bas **dans** l'app (les sondes PCM étaient identiques).

## Ce qui est prouvé ici (sans appareil)

À compléter avec les nombres exacts des commandes lancées sur cette branche (voir le message du dépôt). En résumé, avant l'écoute :

- Les interrupteurs nouveaux partent coupés. Une clé absente reste fausse, ou « off » pour les attributs.
- La garde de mode n'écrit rien tant qu'elle est coupée. Allumée, elle ne coupe pas un vrai appel ni le Bluetooth d'appel.
- Le banc voix (`mode_telephone.py`) montre qu'une voix filtrée « téléphone » reste basse au-dessus de 4 kHz : la sonde actuelle ne la sépare pas d'une parole.
- La phase et les canaux : une voix G = −D s'annule en mono ; le joint stéréo sain et le mono dupliqué ne font pas ce trou (banc `phase_canaux.py`).
- La forme (grave, aigu, écho, chute) se calcule sur des signaux connus (`mesure.py --valider`). Ce n'est pas une cause sûre tant que la fiche de l'appareil ne l'a pas lue.
- Le rapport complet met ces lignes dans un seul texte, et ne recopie pas deux fois la ligne Chemin.

## Ce qui reste à vérifier sur l'appareil

Tout ce qui parle du son **entendu**. Aucun banc de ce dépôt n'a joué France 24 sur la box ni sur le téléphone de Lionel.

## Protocole unique

Un seul APK : l'artefact du build de test de cette branche (nom `claude/…`, publication coupée). Pas la release `zuno-tv`. Pas `phone-latest`.

Le même fichier s'installe sur la box et sur le téléphone : c'est le lecteur Zuno (Media3). L'essai mpv (OpenSL / AudioTrack / AAudio) est dans l'app **7 Motion**, pas dans cet APK. Il reste coupé. On ne publie pas 7 Motion pour l'essayer.

1. Installer l'APK de test par-dessus Zuno. Ouvrir une chaîne qui sonne mal, **sans** toucher aux interrupteurs. Le son doit être celui d'avant. S'il a changé, s'arrêter et le dire : un interrupteur n'est pas resté coupé.
2. Réglages → Diagnostic du son. Tout doit être sur coupé, sauf les replis déjà connus (Focus Zuno, Hors app arrêt, Passage attendre, Repli par chaîne). Attributs : coupé. Chaîne Media3 : Zuno. Contenu : film. Mode : inchangé.
3. Laisser la chaîne mauvaise ouverte. Appuyer sur **Rapport son complet**. Attendre la chaîne (10 s) puis le son témoin (10 s). Ne rien envoyer. Appuyer sur **Copier le rapport**.
4. Lire, dans l'ordre, la section **Angles** :
   - **Chemin** (dans Système) : mode, haut-parleur d'appel, Bluetooth appel.
   - **Attributs** : doit dire essai coupé, contenu film (ou parole seulement si la voix claire était déjà allumée).
   - **Effets** : catalogue, fréquence, spatialiseur. Présent n'est pas allumé.
   - **Tampon** et **Format** : underruns, fréquence piste, fréquence mélangeur, vitesse.
   - **Phase** : corrélation gauche/droite. ≤ −0,70 = voies opposées.
   - **Flux** : signalisation AAC, débit, SBR, horloge.
   - **État** : combien de sources ont du son, et ce qui restait au dernier Home ou au dernier zap.
   - **Forme**, **Écho**, **Chute** : grave/milieu, aigu/milieu, score d'écho, baisse en dB.
5. Refaire le bouton sur une chaîne qui sonne bien, si on en a une. Comparer les deux textes. Ne pas allumer deux essais en même temps.
6. Essais, un par un, puis recouper avant le suivant. Chacun rouvre la chaîne ou attend le zap suivant. Le témoin du rapport, lui, ne laisse pas Spectre allumé :
   - Mode : forcer normal. Seulement si Chemin ne dit pas déjà normal. Pas pendant un appel.
   - Attributs : un cran (film, puis musique, puis parole, puis défaut Media3). Écouter. Revenir à coupé.
   - Contenu : inconnu. Seulement si Attributs est sur coupé. Écouter. Revenir à film.
   - Chaîne Media3 : essai. Le MP2 peut se taire. Écouter. Revenir à Zuno.
7. Sur **7 Motion** (pas cet APK) : Réglages du lecteur, sortie mpv, un nom parmi OpenSL, AudioTrack, AAudio, puis zap. Recouper : on remet OpenSL, le défaut de media_kit. Ne pas publier cette app.

Garder les textes copiés. Ils départagent le tableau. Ils ne réparent pas le son.
