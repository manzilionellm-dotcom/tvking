# Portage The Few — Windows, Samsung TV, LG TV

Ce document fait le point HONNÊTE sur les 3 nouvelles cibles, leur état réel, et
ce qu'il reste à faire (toi + un appareil réel) pour publier. L'app reste UNE
seule base de code Flutter : même backend, même panel, même UI « 10-foot ». Seul
le **moteur de lecture vidéo** change selon la plateforme (c'est inévitable :
chaque OS TV impose le sien).

| Plateforme | Lecteur vidéo | Build CI | État | Test final |
|---|---|---|---|---|
| Android TV / Fire TV | Media3/ExoPlayer (natif) | `build-tv.yml` → `.apk` | ✅ en prod | OK |
| **Windows (PC)** | media_kit (libmpv) | `build-windows.yml` → `.zip` | ✅ compile + lecture | Sur un vrai PC |
| **Samsung TV (Tizen)** | video_player_avplay (AVPlay natif) | `build-tizen.yml` → `.tpk` | 🟡 build de prévisualisation | Vraie TV 2021+ + certif Samsung |
| **LG TV (webOS)** | — (pas de SDK Flutter public) | — | ⛔ pas faisable proprement en 2026 | voir plus bas |

---

## 1. Windows (PC) — PRÊT à tester

- Point d'entrée : `lib/main_windows.dart`.
- Stockage : SQLite via `sqflite_common_ffi` (le PC n'a pas le SQLite d'Android).
- Lecture : `media_kit` (libmpv, le même moteur que VLC) — lit HLS / MPEG-TS /
  MP4, avec reconnexion auto pour les flux IPTV instables.
- Navigation : **clavier** (flèches = télécommande, Entrée = OK, Échap = Retour).

**Comment tester :**
1. Onglet **Actions** GitHub → workflow « Build The Few (Windows) » → dernier run
   → télécharge l'artefact `TheFew-Windows` (ou la release `windows-latest`).
2. Décompresse le `.zip`. **Garde tous les fichiers ensemble** (l'`.exe` a besoin
   de ses `.dll` voisines, dont libmpv).
3. Lance `tv_king.exe`.

**À valider sur un vrai PC** : la lecture vidéo (le CI compile, il ne lance pas
l'app). Si une chaîne ne s'ouvre pas, note l'URL pour qu'on ajuste les options
libmpv.

**Publier sur le Microsoft Store (plus tard)** : empaqueter en **MSIX** (signé)
puis soumettre via le **Partner Center** (compte développeur Microsoft, ~19 $
une fois). On ajoutera un workflow MSIX quand la lecture sera validée.

---

## 2. Samsung TV (Tizen) — build de prévisualisation

- Point d'entrée : `lib/main_tizen.dart`.
- Lecture : `video_player_avplay` (AVPlay/PlusPlayer natif Samsung) — c'est LE
  lecteur recommandé pour l'IPTV sur Tizen (HLS/DASH/MPEG-TS natif, matériel).
- Chaîne de build : **flutter-tizen** (le « flutter » de Samsung) + SDK Tizen,
  tout installé automatiquement par `build-tizen.yml`.
- Le `.tpk` produit est **auto-signé (auteur)** → suffisant pour la compilation
  et le **sideload en Mode Développeur**.

**Contraintes RÉELLES (à connaître) :**
- **TV 2021 ou plus récentes uniquement** (Tizen 6.0+). Les modèles 2020 et
  avant sont bloqués par Samsung — rien à faire.
- **Signer le `.tpk` en CI** : il suffit de TON **certificat AUTEUR** (ton
  identité, créé une seule fois via le **Certificate Manager**, compte Samsung
  GRATUIT). Le **certificat DISTRIBUTEUR** utilisé est celui **par défaut de
  Tizen** (livré avec le SDK) — suffisant pour un `.tpk` signé valide, le test
  émulateur et la **soumission au store** (le store de Samsung **re-signe**).
  Secrets à poser (Réglages GitHub → Secrets and variables → Actions) — **2
  seulement** :
  `SAMSUNG_AUTHOR_P12_BASE64` (ton `author.p12` encodé : `base64 -w0 author.p12`)
  et `SAMSUNG_AUTHOR_PASSWORD` (le mot de passe choisi à sa création). Une fois
  posés, `build-tizen.yml` signe tout seul et publie le `.tpk`.
- **Sideload sur une TV physique précise** (Mode Développeur) : là seulement il
  faut en plus le **certificat DISTRIBUTEUR Samsung lié au DUID** de cette TV.
  On l'ajoutera le jour où une vraie TV Samsung 2021+ est disponible.
- **Note technique honnête** : le `.tpk` auto-signé que le CI tente sans secrets
  ne s'installe de toute façon PAS sur une TV de détail (Samsung exige le certif
  distributeur lié au DUID). C'est pourquoi le CI est « vert » même sans `.tpk`
  signé : il prouve que **tout le portage compile et embarque la pile vidéo
  AVPlay** ; le `.tpk` réellement installable vient avec TES certificats.
- **Publier au Samsung Apps TV** : compte **Seller Office** (passer en « Partner
  Group » pour distribuer hors USA), soumission du `.tpk`, revue ~4 semaines.

**Ce qu'il me reste à faire** : itérer le workflow jusqu'au `.tpk` vert (la
chaîne Tizen est lourde, 1-2 réglages possibles). **Ce qu'il te faut** : une TV
Samsung 2021+ en Mode Dev pour le 1er essai, et (pour aller plus loin) créer le
certificat Samsung une fois.

---

## 3. LG TV (webOS) — pas faisable proprement aujourd'hui

**La vérité, sans enrobage :** en 2026 il n'existe **AUCUN SDK Flutter public
pour webOS**. LG en développe un avec Google (« flutter-webos »), annoncé à
Google I/O 2025, **toujours en bêta fermée** — le dépôt public est vide.

Les seules options aujourd'hui, et pourquoi aucune n'est bonne pour NOUS :

1. **Port Flutter natif** → impossible (SDK pas public).
2. **Flutter Web emballé en app webOS (.ipk)** → l'interface passerait, mais la
   **lecture IPTV casse** : le navigateur webOS ne lit pas le **MPEG-TS brut**
   de façon fiable et son support HLS est vieux (plusieurs années de retard). Il
   faudrait réécrire toute la lecture en JavaScript (hls.js + APIs média webOS).
3. **Réécriture native webOS** (JS/React) → on jette tout le travail Flutter.

**Recommandation :** on **attend la sortie publique de `flutter-webos`** (visée
2026) pour faire un vrai port propre, comme Samsung. Dès qu'il sort, le portage
sera rapide (même approche que Tizen : un `main_webos.dart` + un lecteur natif).
En attendant, **ne PAS livrer un webOS bancal** : ça abîmerait l'image « app de
grande valeur ». Pour un client LG pressé : la **clé Fire TV / box Android**
branchée en HDMI fait tourner l'app Android TV, qui est, elle, excellente.

**Pour publier le jour J** : compte **LG Seller Lounge** (gratuit), app en
`.ipk`, revue ~5-10 jours.

---

## Architecture du lecteur (pour mémoire)

`TvPlayerScreen` est devenu une **façade** : chaque plateforme **injecte** son
lecteur au démarrage via `registerTvPlayer(...)`. Résultat :
- Android TV → lecteur natif Media3 (défaut, inchangé).
- Windows → `DesktopPlayerScreen` (media_kit).
- Samsung → `TizenPlayerScreen` (video_player_avplay).

Chaque lecteur spécifique n'est importé QUE par son `main_*.dart`. Le build
Android TV ne voit donc jamais media_kit ni AVPlay : sa compilation reste propre
et légère, exactement comme avant.
