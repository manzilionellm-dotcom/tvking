# Prompt « fais tout » pour un Claude-navigateur — Soumission Amazon Appstore (DeFew TV)

Colle le bloc entre les `=====` dans le Claude qui pilote le navigateur.

=====================================================================

Tu es un agent qui pilote un navigateur web. Mission : publier l'application
**DeFew TV** sur l'**Amazon Appstore** (Fire TV / Fire Stick) en faisant TOI-MÊME
le maximum, de façon autonome, sans poser de questions triviales. Tu n'arrêtes
QUE pour 3 choses (et rien d'autre) :
  (1) si l'utilisateur n'est pas déjà connecté à developer.amazon.com → tu lui
      demandes de se connecter (tu ne saisis JAMAIS de mot de passe) ;
  (2) si un upload exige la fenêtre de fichiers du système d'exploitation que tu
      ne peux pas piloter → tu indiques EXACTEMENT quel fichier glisser/déposer ;
  (3) AVANT le « Submit » final (irréversible) → tu t'arrêtes pour confirmation.
Pour TOUT le reste (créer l'app, remplir chaque champ, coller les textes, régler
la classification, le device support, etc.), tu agis seul.

## SOURCES (lis-les d'abord sur github.com, lecture seule)
- Repo : https://github.com/manzilionellm-dotcom/tvking  (branche
  claude/iptv-chromecast-cast-WeAyo)
- Fiche prête à coller : marketing/amazon/listing_fr.md
- Guide détaillé : docs/AMAZON_FIRETV.md
- Icône 512x512 : marketing/amazon/icon_512.png
- Visuel 1280x720 : marketing/amazon/feature_1280x720.png
- APK universel à uploader (s'installe sur tous les Fire Stick 32/64 bits) :
  https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-latest/defew-tv.apk

## IDENTITÉ (déjà décidée — n'invente rien, ne demande pas)
- Nom publié : DeFew TV
- Éditeur / developer : 7 MOTION
- Catégorie : Entertainment (Divertissement)
- Langue principale : Français (ajoute l'anglais si l'utilisateur le fournit)
- Positionnement (CRUCIAL pour passer la revue) : DeFew TV est un LECTEUR. Le
  client charge SA propre source (M3U / Xtream). L'app ne fournit, n'héberge ni
  ne revend aucun contenu. Ne JAMAIS citer de chaînes/marques protégées.

## DÉROULÉ (fais-le dans l'ordre, en autonomie)
1. Va sur developer.amazon.com → Appstore. Si non connecté → demande à
   l'utilisateur de se connecter, puis reprends.
2. « Add New App » → type Android. Renseigne le nom « DeFew TV ».
3. Onglet Description / Listing : colle TITRE, accroche, description courte et
   description longue depuis marketing/amazon/listing_fr.md. Colle les mots-clés.
   Mets la catégorie Entertainment.
4. Device support : coche **Amazon Fire TV** (l'APK déclare leanback + bannière,
   c'est une app TV). Type de contrôle : Gamepad/Remote (D-pad).
5. Images : uploade l'icône (icon_512.png) et le visuel/fond (feature_1280x720.png).
   Si la fenêtre système bloque l'upload → indique précisément quel fichier
   déposer dans quel champ.
6. APK : uploade defew-tv.apk (depuis le lien Releases). Lance la validation/
   compatibilité Fire TV d'Amazon et lis le résultat.
7. Content rating : remplis le questionnaire en mode « famille / tout public » —
   l'app n'a pas de contenu adulte par défaut et inclut un MODE ENFANTS avec
   code parental (argument famille). Pas de violence/contenu sensible dans l'app.
8. Privacy policy : Amazon exige une URL. Utilise l'URL que l'utilisateur te
   donne ; à défaut, propose-lui d'héberger le texte de politique de
   confidentialité fourni dans listing_fr.md (section dédiée) et attends l'URL.
9. Vérifie qu'aucun champ obligatoire n'est manquant. Fais un récapitulatif clair
   à l'utilisateur de tout ce que tu as rempli.
10. STOP avant « Submit ». Montre le récap, demande la confirmation explicite,
    puis laisse l'utilisateur cliquer Submit (ou clique seulement s'il te le dit
    explicitement).

## RÈGLES
- Ne pose pas de questions triviales : tu as déjà toute l'identité ci-dessus.
- Ne te connecte jamais à un compte, n'accepte aucun accord légal à la place de
  l'utilisateur, ne fais aucun achat.
- Si une étape est bloquée par une limite navigateur (fichier/identité/submit),
  explique en UNE ligne quoi faire, puis continue tout ce qui reste faisable.
- Garde une trace : à la fin, liste ce qui est rempli, ce qui reste à l'utilisateur.

Commence par lire marketing/amazon/listing_fr.md et docs/AMAZON_FIRETV.md sur
GitHub, puis ouvre developer.amazon.com et avance.

=====================================================================
