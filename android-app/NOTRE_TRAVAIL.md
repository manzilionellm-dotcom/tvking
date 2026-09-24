# 📖 Notre travail — BLACK7 ROYAL

> Le livre de bord de ce qu'on a construit ensemble, toi et moi.
> Application IPTV **BLACK7 ROYAL** (Flutter) + panel admin + backend Cloudflare.
> Branche : `claude/github-commit-access-YDUAv` · PR #4 · juin 2026.

---

## 🎬 Le lecteur

- **Enregistrement réparé** : fini les fichiers vides. Plusieurs corrections —
  redirections cross-protocole, **User-Agent aligné sur le lecteur**, et au
  final l'**enregistrement par capture d'écran** (MediaProjection),
  *imblocable* même sur les serveurs « 1 connexion ».
- **Capture d'écran intelligente** : autorisation demandée **une seule fois**
  par session, et un bouton discret **« Arrêter le partage »** dans la
  notification.
- **Bouton ⬇️ Télécharger** directement dans le lecteur (pour les films).
- **Fluidité** façon Netflix (`video-sync=display-resample`, anti-saccades).
- **Mode anti-coupure** : le lecteur bufferise jusqu'à ~1 min et **prend du
  retard au lieu de casser** quand la connexion faiblit.

## 📺 La connexion / les sources

- **Serveurs par défaut côté serveur** (panel) — aucune URL IPTV en dur dans
  l'app (règle n°2 d'AGENTS.md respectée).
- **Activation par MAC** : le client donne sa MAC, tu pousses sa source
  (Xtream/M3U) depuis le panel, l'app la charge toute seule.
- **« Activer l'app »** → ouvre **directement WhatsApp** avec la MAC.
- **Connexion par code** (Xtream, serveur prédéfini caché) **+** option
  **« J'ai ma propre source »** (M3U **ou** Xtream perso).
- **Bouton Actualiser** + **auto-refresh toutes les 24 h**.

## 🍿 VOD — films à la demande

- **Catalogue de films** récupéré du serveur Xtream.
- **Téléchargement hors-ligne** (façon Netflix) : progression, **pause /
  reprise**, reprise après coupure, lecture **sans connexion**, suppression.

## 🎛️ Le panel admin

- Page **« Serveurs »** : ajouter / renommer / changer autant de liens que
  tu veux (« Serveur 1, 2, 3… »).
- Activation par MAC avec **plans d'essai GRATUITS** (Test 2 h / 24 h / 48 h,
  0 crédit) + assignation de la source (Xtream/M3U) à l'activation.

## 📡 Le cast

- Retrait de l'option **« Cast par QR code »** (on garde les vraies TV).

## 🏠 Le nouvel accueil « simple »

- Navigation **Pays → Catégories → Chaînes**, pensée pour être évidente
  pour tous.
- Pays **détectés automatiquement**, tuiles colorées, **❤️ favoris** et
  **🕐 récemment regardé**.
- **Zone Cinéma & Séries verrouillée** par **empreinte / Face ID** ou
  **code PIN** (00000 par défaut, modifiable).

## 🏷️ L'identité

- Rebrand complet **7 MOTION → BLACK7 ROYAL** : nom, logo, icône de l'app,
  page d'accueil, panel — partout.

---

## 🗓️ Journal des étapes (dans l'ordre)

1. Enregistrement : suspendre la lecture pendant la capture (mode 1 connexion)
2. Connexion : serveurs par défaut côté serveur (URL cachée)
3. Client : retrait total du M3U côté interface + serveur prédéfini
4. Panel admin : gestion des serveurs par défaut (Serveur 1/2/3…)
5. Activation par MAC : pousser la source (Xtream/M3U) depuis le panel
6. Activation : plans d'essai GRATUITS (2 h / 24 h / 48 h)
7. Client : réactiver la connexion par code (user+mdp) en plus du push MAC
8. Landing : domaine dynamique (n'expose plus le domaine en dur)
9. Enregistrement : aligner le User-Agent + retenter sur 403
10. Enregistrement : capture d'écran (MediaProjection) — imblocable
11. Accueil : bouton « Actualiser » + auto-refresh 24 h
12. Source : option « J'ai mon propre M3U »
13. Source : « Activer l'app » → WhatsApp direct avec la MAC
14. Lecteur : fluidité du rendu (anti-judder)
15. VOD : catalogue de films + téléchargement hors-ligne
16. Rebrand : 7 MOTION → BLACK7 ROYAL (nom + logo partout)
17. Source : retrait « Vérifier mon abonnement » + Xtream dans la feuille perso
18. Lecteur : mode anti-coupure (buffer adaptatif)
19. VOD downloads : correction d'un bug de compilation + d'une fuite
20. Lecteur : bouton Télécharger (hors-ligne) dans la barre du haut
21. Capture d'écran : autorisation demandée une seule fois
22. Capture d'écran : bouton « Arrêter le partage » dans la notification
23. Cast : retrait de l'option « Cast par QR code »
24. Accueil : nouveau design « simple » (Pays → Catégories)

---

*Construit ensemble. Le code, on l'a — le reste (tests, serveur fiable,
support), c'est toi qui le construis. 🚀*
