# UX du diagnostic — un seul rapport son

Branche `claude/son-11-rapport-unique`, partie de `claude/zuno-mesures-audio` (474969c2).

Le client n'est pas développeur. Il ne doit pas lire onze fiches. Réglages → Diagnostic du son a un bouton **Rapport son complet**. En moins de 30 secondes il enchaîne l'état du système, 10 secondes de la chaîne si elle joue encore, puis le son témoin, et il affiche **un** texte à copier.

Ce texte ne change pas le son. Les interrupteurs enregistrés restent où ils sont (coupés par défaut). Le spectre, s'il était coupé, est allumé seulement le temps de la mesure, puis remis. La copie PCM ne filtre pas.

On n'a pas entendu la box. On n'a pas « résolu » le son « vieille radio ».

## PROUVÉ

### Le fichier témoin, mesuré sur cette machine

Commande :

```text
ffprobe -v error -show_entries format=duration -show_streams android-app/assets/audio/son_temoin.m4a
```

Sortie utile : AAC-LC, 48 kHz, stéréo, 160 kb/s, durée **10,000 s** exactement. Le bouton qui attend 10 secondes couvre donc le fichier entier (5 s de voix, puis 5 s de bruit), il ne le coupe pas au milieu.

Ensuite le même filtre que le lecteur (passe-haut Butterworth ordre 2, 4 kHz, Q = 1/√2, mélange des deux voies, 512 échantillons d'échauffement ignorés — les mêmes formules que `AudioSpectrum.start` / `push`) :

| Morceau | Énergie au-dessus de 4 kHz | Corrélation gauche/droite |
| --- | --- | --- |
| 0–5 s (voix) | 0,3 % | +1,00 |
| 5–10 s (bruit) | 75,0 % | +0,95 |
| 0–10 s | 70,4 % | +0,96 |

Les seuils du lecteur sont 12 % (bande basse) et 40 % (bande large). La voix du témoin est basse, le bruit est large, les voies vont ensemble. Ce n'est pas une écoute : c'est le calcul sur le fichier embarqué.

Conséquence pour le verdict : une chaîne de parole à 0,9–3,6 % (déjà mesurée ailleurs, normale pour de la voix) n'est « source étroite » que si le **bruit** du témoin, lui, sort large. Si le témoin sort bas lui aussi, on ne accuse pas la chaîne.

### Le verdict, sur des phrases (pas sur une oreille)

Les tests sont dans `android-app/test/features/player/sound_full_report_test.dart`. Ils donnent un mot et un niveau de confiance à partir des phrases que le lecteur écrit déjà :

- « ⚠ chemin d'appel », « écouteur d'appel » ou « Bluetooth appel allumé » → **chemin d'appel détecté** (confiance haute). « Bluetooth appel coupé » ou « pas de chemin d'appel » ne suffisent pas. Dire « Bluetooth oui » sans cette phrase ne suffit pas non plus.
- Corrélation ≤ −0,70 ou « voies opposées » → **phase inversée**. −0,69 ne suffit pas. Si le chemin d'appel est là en même temps, le verdict reste le chemin d'appel, et la phase est notée à part.
- Chaîne « bas » (≤ 12 %) et dernière seconde du témoin « large » (≥ 40 %) → **source étroite**. Les deux bas → **rien d'anormal côté app**, confiance basse, avec la phrase « la chaîne et le témoin sont étroits ».
- Son large, chemin normal, voies ensemble → **rien d'anormal côté app**, confiance haute.
- « clair » baisse la confiance d'une source étroite. « sourd » alors que les mesures sont larges baisse la confiance de « rien d'anormal ». Une autre app qui joue baisse aussi, et le texte le dit.
- Une ligne en double n'est écrite qu'une fois. Le témoin ne recopie pas les lignes déjà dites pour la chaîne.
- Une URL et un mot de passe dans la fiche sortent en `[url]` et `[secret]`.
- Deux angles qui enregistrent un ajout : les deux phrases apparaissent, triées, une seule fois. Le même identifiant une deuxième fois remplace. Un ajout qui plante n'empêche pas le texte. Un ajout qui dit « voies opposées » change le verdict sans qu'on édite la fiche.

La sortie de `flutter test` est collée en bas de ce fichier après exécution.

## Ce que le bouton fait

1. Il lit la dernière fiche (codec, chemin, effets, lectures, spectre, phase).
2. Si une chaîne est encore ouverte (`NowPlaying` non vide), il écoute **10 secondes** de plus.
3. Il joue `assets/audio/son_temoin.m4a` pendant **10 secondes** avec le même lecteur que les chaînes.
4. Il affiche un texte. **Copier le rapport** le met dans le presse-papiers. Rien n'est envoyé.

Les trois questions (clair / sourd, Bluetooth oui / non, autre app oui / non) se répondent en un mot, avant ou après. Changer un mot recalcule le texte, sans relancer le son. Pas de réponse = « pas dit ».

Durées prévues : 10 + 10 secondes si la chaîne joue, 10 secondes sinon, plus 0,4 seconde pour le dernier chiffre. Toujours sous 30 secondes. C'est testé (`SoundReportPlan`).

## Point d'extension (les autres angles)

Fichier `lib/features/player/domain/sound_report_parts.dart`.

- Une ligne déjà écrite dans la fiche du lecteur remonte toute seule, dédupliquée. Il n'y a rien à modifier ici.
- Une phrase qui n'est pas dans la fiche : une ligne dans `installSoundReportParts`, avec un id stable. Le même id une deuxième fois remplace, il ne double pas.
- Dans ces phrases, « chemin d'appel », « écouteur d'appel », « Bluetooth appel allumé », « voies opposées » ou une corrélation ≤ −0,70 sont lus par le verdict. Une ligne « Spectre… » est seulement montrée : elle ne remplace pas la fiche de la chaîne ni celle du témoin.

On n'a pas modifié le décodeur, le focus, le volume, ni les fiches des autres angles.

## HYPOTHÈSE

Le mauvais son décrit (« vieille radio », « dans un trou », « comme un appel », « deux sons qui se battent ») correspond aux quatre mots du verdict, dans cet ordre : chemin d'appel, phase inversée, source étroite, rien côté app. Confiance **60 %** sur ce classement, pas sur la cause réelle : les essais déjà faits (décodeur, chevauchement, volume, passe-bas dans l'app) ont écarté d'autres pistes, mais cette branche ne mesure pas une box.

Confiance **haute** seulement quand la fiche contient la phrase correspondante. Sans spectre sur la chaîne (interrupteur coupé au moment où on l'a regardée, ou chaîne déjà fermée), le verdict tombe sur « rien d'anormal côté app » avec confiance **basse**, et le texte le dit. Ce n'est pas une innocence : c'est un manque de chiffre.

## À VÉRIFIER SUR L'APPAREIL

Sur la box, ou sur le Samsung, avec la chaîne qui sonne mal (France 24, France 2, France Info ou BEIN) :

1. Allumez **Spectre : mesuré** (Réglages → Diagnostic du son). Laissez la chaîne **ouverte** au moins 10 secondes. Ne changez pas les autres interrupteurs.
2. Sans fermer le lecteur, ouvrez Réglages → Diagnostic du son. Si le lecteur se ferme en quittant l'image (c'est le cas aujourd'hui quand on change d'écran), le rapport dira « pas ouverte pendant ce rapport » et reprendra la dernière fiche. C'est voulu : on ne rouvre pas un flux tout seul.
3. Répondez en un mot : le son est-il clair ou sourd, le Bluetooth est-il branché, une autre app joue-t-elle.
4. OK sur **Rapport son complet**. Attendez la fin (le bouton affiche l'étape). Écoutez le témoin : voix, puis bruit.
5. OK sur **Copier le rapport**. Envoyez le texte.

Lecture du premier mot :

- **chemin d'appel détecté** : le texte « Système » doit contenir « chemin d'appel », « écouteur d'appel » ou « Bluetooth appel allumé ». Coupez l'appel ou l'app qui tient le micro, relancez. Si le mot disparaît et que le son devient normal, la piste est confirmée sur cet appareil.
- **phase inversée** : la fiche doit montrer une corrélation négative (≤ −0,70) ou « voies opposées ». Notez si c'est la chaîne, le témoin, ou les deux.
- **source étroite** : la chaîne est « bas », la dernière seconde du témoin est large (le bruit, vers 70 % sur le fichier, si l'appareil ne le filtre pas). Le bruit du témoin doit s'entendre clair. S'il s'entend sourd alors que le texte dit large, le chiffre et l'oreille ne disent pas la même chose : renvoyez le texte, ne concluez pas.
- **rien d'anormal côté app** : regardez la confiance. « Basse » plus « les deux sont étroits » veut dire que l'appareil peut encore colorer le son après l'app. « Haute » plus un spectre « présent » veut dire que les aigus sont dans l'app : le défaut entendu n'est pas un filtre de Zuno.

Ne publiez pas ce texte s'il contient encore une adresse de flux : il ne devrait pas, le filet remplace ça par `[url]`.
