# CLAUDE.md — NOVA+ · Le lecteur IPTV le plus fluide et le plus personnel d'Android TV

## MISSION
Construire une app que l'utilisateur ressent comme MAGIQUE dès la première seconde : elle s'allume vite, joue chaque chaîne du premier coup, comprend sa langue toute seule, se souvient de ce qu'il regarde, et le prévient quand son match commence. Objectif : qualité « TiViMate, en mieux et plus personnel ». Tu ne livres rien de banal.

## DÉFINITION DE « MAGIQUE » (règles, pas slogans)
1. ZÉRO friction : tout ce qui peut être deviné est deviné (langue, dernière chaîne, source). On ne demande à l'utilisateur QUE le strict nécessaire.
2. ÇA MARCHE TOUJOURS : une chaîne qui ne lit pas est un bug prioritaire. Préférer le retard à la coupure. Toujours un repli, jamais un écran mort.
3. INSTANTANÉ ressenti : démarrage à froid rapide, zapping immédiat, focus qui répond au doigt et à l'œil. Si une action attend, montrer un état (jamais un gel silencieux).
4. PERSONNEL : home avec « Reprendre / Récemment vues / Tes favoris en direct ». L'app se moule à l'usage, pas l'inverse.
5. BEAU AU REPOS : fond jamais noir pur, texte jamais blanc pur, accents désaturés, rouge réservé au LIVE, contraste WCAG AA minimum. Lisible à 3 mètres à la télécommande.
6. DÉTAIL SOIGNÉ : transitions de focus nettes, sons/réactions cohérents, aucune secousse de layout, aucune image qui « pop ». Le soin est la fonctionnalité.

## STACK (ne pas dévier sans mon accord)
- Web : Next.js 16 (static export), React 19, TypeScript strict, Tailwind 4.
- Lecture : hls.js (+ fallback HLS natif / <video> direct). Résilience DÉJÀ réglée (buffer ~60s, retries, recover).
- Wrapper : Android Kotlin WebView (`nova-tv-wrapper/`), proxy CORS natif (`shouldInterceptRequest`), WebViewAssetLoader, minSdk 21.
- État : composants purs + `useSyncExternalStore`. Parsers purs : `m3u.ts`, `xmltv.ts`, `epg.ts`.
- i18n : 10 langues auto (`navigator.languages`) + RTL (arabe), repli anglais.
- UI 10-foot : canvas 1920×1080, tailles `rem` pilotées par `100vw`, safe-area ~5%, focus D-pad (ring + scale + élévation).

## INVARIANTS — NE JAMAIS CASSER
1. Le proxy CORS natif (sinon 0 chaîne).
2. La résilience hls.js (retard > coupure).
3. Le scaling 720p→4K (rem/100vw) et les safe-areas.
4. L'i18n + RTL + repli anglais.
5. La porte d'activation / format MK: (compat Worker Cloudflare).
6. Aucun secret, clé ou keystore dans le code ou les commits.

## CAP PRODUIT (ordre de priorité quand je te laisse choisir)
1. Fiabilité de lecture : chemin lecteur natif ExoPlayer/Media3 en repli (HEVC, MPEG-TS, audio multicanal) quand hls.js ne suffit pas. C'est LE saut de qualité n°1.
2. Personnalisation home : rails Reprendre / Récents / Favoris en direct + reprise de la dernière chaîne au lancement.
3. Sport magique : alertes « ton match commence » (moteur EPG `events.ts`) avec accès en un clic.
4. Thèmes : système de tokens couleur → 9 modes (Classic, Modern, Dark Cinema, Neon, Minimal, Creator, Luxury, Dynamic AI, Accessibility Plus).
5. Confort : sélection audio/sous-titres, ratio/zoom, cache IndexedDB de la playlist/EPG pour démarrages chauds instantanés.

## WORKFLOW (à chaque tâche)
1. LIRE le code concerné avant toute proposition.
2. PLAN court : étapes + fichiers exacts touchés. Pour toute tâche non triviale, attends mon "go".
3. PÉRIMÈTRE : ne touche QUE les fichiers nommés. Aucun refactor, renommage ou ajout non demandé.
4. CODER : petits diffs ciblés, style identique à l'existant. Aucune nouvelle dépendance sans demander.
5. VÉRIFIER : `npm run lint` + `npm run build` doivent passer. Tu corriges TES erreurs avant de rendre. Pense aux cas limites (source vide, hors-ligne, 4K, RTL, box bas de gamme).
6. COMMIT : un commit atomique, message conventionnel en français (`feat(nova): …`, `fix(wrapper): …`). Jamais de push sans ma demande.

## COMMANDES
`npm install` · `npm run dev` · `npm run build` · `npm run lint` · APK via `.github/workflows/build-nova-tv.yml`.

## RÉPONSES
- Pas d'intro, pas de "voici", pas de répétition de ma demande, pas d'excuses.
- Ambigu ou risqué pour le build → UNE question courte avant de coder.
- Toujours fournir : ce que tu as changé · comment vérifier à l'écran · ce qui pourrait casser.
- Code réel et complet. Jamais de pseudo-code ni de "// reste inchangé" sans mon autorisation.

## INTERDITS
- Modifier hors périmètre, refactor non demandé, dépendances surprises.
- Masquer une erreur lint/TS au lieu de la corriger.
- Commit qui ne builde pas. Secret dans le repo. Suppression définitive sans confirmation.
- Livrer du « correct mais fade » : si c'est banal, ce n'est pas fini.

---

<!-- Note projet historique conservée (breaking changes Next.js) -->
@AGENTS.md
