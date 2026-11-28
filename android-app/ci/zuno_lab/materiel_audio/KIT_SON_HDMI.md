# SHIELD / petite box : accord du son, du titre et de l’image

Sur la box de test seule, ouvrir les deux mires automatiques. Leur audio porte 440 Hz pour A et 660 Hz pour B. Activer le bandeau d’informations pour rendre le titre visible. Enregistrer environ 30 à 45 s couvrant A → B → A sur une entrée HDMI de capture autorisée. Le fichier doit réunir vidéo du même écran, audio de cette même sortie et horodatages des deux pistes. Pour une caméra, cadrer frontalement toute la dalle et fournir le rectangle intérieur en pixels. Une capture HDMI mesure le signal de la sortie et ne mesure pas la latence physique de la dalle.

Utiliser Python avec Pillow et NumPy, FFmpeg, ffprobe et Tesseract. Depuis la racine du dépôt, se placer dans `android-app/ci/zuno_lab/materiel_audio`. La sonde de fréquence est l'implémentation commune du dossier voisin `synchronisme`. Le fichier d’entrée reste local.

```sh
python capture_hdmi.py deux-zaps-hdmi.mkv accord-son-titre-image.json
# Exemple de rectangle intérieur si le film cadre aussi le pourtour :
python capture_hdmi.py film-de-la-dalle.mkv accord-dalle.json --cadre 160:90:1600:900
```

Le JSON ne contient que les PTS, le résultat de la lecture du titre A/B, les compteurs de mire et les classes de ton. Toutes les 240 ms au minimum, le contrôle recherche le titre dans le même cadre que la bande binaire et deux compteurs croissants. Deux fenêtres PCM de 100 ms encadrent le PTS de la capture. Elles doivent porter la seule fréquence caractéristique attendue. Silence, fréquence étrangère, contenu hors cadre, titre illisible ou discontinuité temporelle supérieure à 20 ms rendent la cellule inexploitable. Un compteur invisible ne peut pas être remplacé par une réussite du réseau. Le script ne produit aucun enregistrement audio isolé, copie de l’écran ou texte de programme.

Calibration contrôlée, sans application : 9 échantillons de mire A avec titre « Mire A » et vraie piste à 440 Hz ; 7 triplets complets. Les deux échantillons de bord manquent des 100 ms d’audio d'un côté. Cette calibration ne compte pas comme un essai sur une box.
