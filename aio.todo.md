# À compléter (non lisible sur le site — rien n'a été inventé)

- Débits / bitrates / bande passante minimale : `tech.bitrate` = null
- Nombre de chaînes : `tech.channelCount` = null (le site dit explicitement qu'il n'en vend pas, sans donner de chiffre)
- Résolution d'image des flux : `tech.maxResolution` = null. Le README parle d'un canvas 16:9 qui scale jusqu'au 4K pour l'interface, ce n'est pas une résolution de flux annoncée.
- Délai d'activation en minutes : `tech.activationMinutes` = null. Seule formule publiée : « activation instantanée ».
- Tutoriel d'installation par appareil (Firestick, Android TV, Apple TV, etc.) : les pages Télécharger et Activer donnent des consignes courtes, pas un pas à pas avec ancres. Pas de HowTo généré.
- Images : aucune balise `<img>` sur les pages. Rien à décrire. Les SVG de `public/` ne sont pas des images de contenu.
- Vidéos : aucun `<video>` ni iframe YouTube/Vimeo. Pas de transcription à injecter. Le lecteur de l'app démo n'embarque pas de média.
- Avis clients / note / image produit : absents. Pas d'`aggregateRating` ni d'image Product.
- Page `/start` : texte encore « TV King — 24h trial, no card », sans prix dans `app/lib/plans.ts`. Non transformé en offre Product, car l'accueil et les forfaits décrivent seulement les licences Zuno 9,99 € / 15 €.
- Deux URL coexistent dans le dépôt : hôte `https://tvking.vercel.app` (`app/robots.ts`, déploiement) et `https://zuno.7themotion.com` (`metadataBase`, mentions, sitemap). Les deux sont recopiés, aucun n'a été choisi à la place de l'autre.
- Catalogue démo (`app/lib/data.ts`, pages Films / Sport / Formation) : titres fictifs (Champions League, etc.). Non repris dans `llms.txt` ni dans le JSON-LD, ce n'est pas l'offre commerciale.
- Stats revendeur : tirets « — », aperçu non branché.
- Google Play : « publication en cours » / « bientôt ». Pas une plateforme disponible.
- Horaires du support WhatsApp : non publiés.
