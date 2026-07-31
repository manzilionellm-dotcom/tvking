# Roadmap tvking

## BUT ULTIME (instruction humaine, 2026-07-31)
Devenir **l'application IPTV mobile n°1 au monde**. Ce but remplace l'ancien
périmètre « TV uniquement » : le mobile est désormais LE cœur du produit.
Trois engagements non négociables :
1. CGU acceptées obligatoirement au premier lancement (l'app ne fournit aucun
   contenu ; liens/playlists fournis par l'utilisateur, sous sa responsabilité).
2. Chaque lien est vérifié avant lecture (jamais envoyé au lecteur s'il est invalide).
3. Zéro spinner : les films se téléchargent d'eux-mêmes (progression déterminée)
   et démarrent instantanément ; toute attente est bornée et expliquée.

## Fait (run-001)
- Baseline mesurée ; CI qa-gates ; tests unitaires logique pure ; focus scope lecteur + BACK + media keys ;
  restauration du focus ; reprise de lecture persistée v1.

## Fait (run-002 — pivot mobile IPTV)
- ConsentGate : CGU versionnées, acceptation obligatoire au lancement (lib consent + tests).
- Cœur IPTV : parseur M3U tolérant + vérification des liens (verifyUrl) + playlist
  persistée v1 + page /tv (import, groupes, badges « lien vérifié », lecture).
- Films : catalogue kind="film", page /films, store downloads v1 (testé),
  auto-téléchargement à progression déterminée → « Lecture instantanée ».
- Mobile-first : barre d'onglets basse <768px, rail latéral masqué, base
  typographique fixe 13px et marges réduites sur téléphone.
- Mini-lecteur flottant façon YouTube (demande humaine + capture de référence) :
  « Réduire » et « Écouteurs » dans le lecteur ; la lecture continue en fenêtre
  flottante avec tous les contrôles dedans (audio seul, pause, suivant,
  agrandir, fermer) ; reprise de position partagée avec le lecteur plein écran.

## Prochain (run-003+, ordre I9)
1. Lecteur vidéo réel (HTML5 <video> HLS) derrière un PlayerService — TTFF/zapping
   mesurables, watchdogs S4 (écran noir, attente > seuil ⇒ erreur claire, jamais de
   spinner) télémétrés. Vérification des liens côté réseau (HEAD/timeout court).
2. Téléchargement réel des films (Cache Storage / OPFS) derrière l'API downloads v1.
3. Import M3U par URL (fetch + CORS proxy) en plus du collage ; EPG (XMLTV).
4. « Ma liste » réelle (persistée v1) + états vides ; recherche fonctionnelle (FTS locale).
5. E2E chemin critique (Playwright) : CGU → accueil → /tv import → lecture → BACK.
6. SBOM + osv-scanner en CI ; goldens visuels mobile + TV.
7. MODULE D/V : stores/analytics — CHECKLIST humaine.
