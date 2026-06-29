# Site officiel 7 MOTION / DeFew TV

Page d'accueil VIP (thème noir/rouge), **un seul fichier** : `index.html`.
Autonome, responsive, sans build. Positionnement « lecteur multimédia » (on ne
vend pas de chaînes — protection légale).

## 1. Personnaliser (2 minutes)
Ouvre `index.html` et modifie **uniquement** le bloc `CONFIG` en haut :

```js
const CONFIG = {
  whatsapp: "447307410512",   // ton numéro WhatsApp, format international SANS "+" ni espaces
  appUrl:  "https://app.7themotion.com/install",  // déjà branché
  tvUrl:   "https://app.7themotion.com/tv",        // déjà branché
  privacyUrl: "https://app.7themotion.com/privacy",
  prices: {
    m1:  { amount: "5,99",  unit: "/ mois"  },
    m6:  { amount: "29,99", unit: "/ 6 mois" },
    m12: { amount: "49,99", unit: "/ an"    }
  },
  currency: "€"   // ou "MAD", "DH"…
};
```

- Le **numéro WhatsApp** alimente tous les boutons (nav, formules, formulaire MAC).
- Le **formulaire MAC** ouvre WhatsApp avec la MAC du client pré-remplie.
- Les **QR codes** (téléphone / TV) sont générés tout seuls vers tes liens.

## 2. Mettre en ligne (au choix)
- **Cloudflare Pages** (gratuit, simple) : nouveau projet → upload de ce dossier → branche le domaine `7themotion.com`.
- **GitHub Pages** : pousse le fichier, active Pages.
- **Via le worker** : on peut servir cet HTML sur `7themotion.com/` directement (demande-moi, je l'ajoute en route worker).

## Notes
- Aucune donnée n'est collectée par la page ; tout passe par WhatsApp (humain, hors-site).
- La lib QR est chargée via CDN ; si elle est bloquée, le lien texte reste affiché.
- Disclaimer légal présent en pied de page (« aucun contenu fourni »).
