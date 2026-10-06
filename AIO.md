# AIO (Sprint) — source unique : aio.config.json

Zuno est une application IPTV (lecteur). Le site vend une licence d'application, pas un bouquet de chaînes. `aio.config.json` ne reprend que des faits déjà écrits sur les pages (accueil, forfaits, FAQ, télécharger, activer, revendeur, mentions).

- `npm run aio:llms` régénère `public/llms.txt`
- `npm run build && npm start` puis `node scripts/aio-check.mjs http://localhost:3000/` : preuve sur HTML brut (Citation Hooks 40–60 mots, JSON-LD parsable, alt, transcription vidéo, /llms.txt)
- Les h3 de la FAQ + le `<p>` de réponse, et le JSON-LD, sont rendus en SSR (`app/layout.tsx`, `app/components/site/CitationFaq.tsx`). Rien n'est dans un accordéon, un lazy-load ou un composant client.
- Product : licences Annuel (9,99 €) et À vie (15 €). Pas de HowTo : aucun tutoriel d'installation pas à pas n'est publié.
- Manques (débit, nombre de chaînes, résolution, etc.) : `aio.todo.md`.

## Anomalie ~97 Mo (page d'accueil déployée)

Mesure du 4 octobre 2026, `curl` sans JavaScript sur `https://tvking.vercel.app/` :

- `Content-Length: 72907` octets (~71 Kio), identique au corps téléchargé. Ce n'est pas ~97 Mio.
- Déploiement `dpl_7vBRcSLhuqMfPdnrkVznpAX4NwNh`, `x-matched-path: /fr`, cache Vercel HIT (âge ~4,7 jours au moment de la mesure).
- Titre : « TV King — Sport, films & formation ». 17 `h2`/`h3` (rangées démo : Reprendre, En direct maintenant, Tendances et titres de cartes). 0 JSON-LD, 0 `img`, 0 image base64.
- Plus gros script inline ~17 Kio (payload RSC). JS + CSS + polices liés ≈ 1,0 Mio.
- Le HTML ne montre ni boucle de rendu ni donnée inline géante.

Ce déploiement ne correspond pas au `main` actuel (accueil marketing Zuno, sans route `/fr`). La cause d'un HTML de ~97 Mio n'est pas reproductible sur l'URL actuelle, et aucun correctif de rendu n'a été appliqué.
