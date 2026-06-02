# 👑 TV King

Application de **streaming TV premium et universelle** (Next.js) pensée pour la
télévision : utilisable à ~3 m, **à la télécommande**, par **tout le monde** —
une personne âgée, un enfant qui ne lit pas encore, ou un amateur de nouveautés.

> **« Personne n'est perdu, jamais. »** Un seul élément a le focus, on ne peut
> pas le perdre, et RETOUR est toujours prévisible. 5 touches suffisent :
> ↑ ↓ ← → + OK.

## Démarrage

```bash
npm install
npm run dev      # http://localhost:3000
```

Naviguez aux **flèches**, **Entrée/Espace** = OK, **Échap/Retour** = revenir.
(La souris fonctionne aussi.)

Au **premier lancement**, choisissez un **profil** (Confort / Enfants /
Standard) — modifiable ensuite dans **Réglages**.

## Scripts

| Commande        | Rôle                                       |
| --------------- | ------------------------------------------ |
| `npm run dev`   | Serveur de développement                   |
| `npm run build` | Build de production (type-check + lint)    |
| `npm run lint`  | ESLint                                     |
| `npm test`      | Tests (vitest : navigation, données, a11y) |

## Fonctionnalités

- **5 univers** : 🏆 Sports · 📺 Chaînes · 🎬 Divertissement · 🧸 Enfants ·
  🗞️ Journal — chacun sa couleur, son icône, ses rangées.
- **Accessibilité universelle** : profils, taille réglable, contraste élevé
  (AAA), réduction des animations, **narration vocale**, mode **repos des
  yeux**.
- **Couche futuriste** (tout désactivable) : éclairage ambiant adaptatif,
  parallaxe, **recherche vocale**, **multi-écran** sport, retours sonores doux.
- **Édition VIP** : finitions dorées, profondeur, halo — le luxe par la finesse.
- **Ma liste**, **recherche**, **fiche détail**, **lecteur** avec « À suivre »
  annulable (jamais de lecture auto forcée).

## Stack & contraintes

Next.js 15 (App Router) · TypeScript strict · Tailwind CSS v4 · **zéro lib de
composants externe** · visuels en **dégradés CSS** · **aucune marque réelle ni
secret** dans le code · cible **Vercel**.

Détails d'architecture et conventions : voir [`CLAUDE.md`](./CLAUDE.md).
Recherche UX/accessibilité sourcée : voir
[`docs/RESEARCH-TV-UX.md`](./docs/RESEARCH-TV-UX.md).
