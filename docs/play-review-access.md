# Accès examinateur Google Play — mode d'emploi

> Réponse au refus « identifiants restreints par l'authentification de
> l'appareil » : l'examen ne doit dépendre d'AUCUNE action côté panel.

## Ce que le build fait désormais

1. **Code d'accès examinateur** : taper `GPLAYREVIEW` comme *identifiant*
   (ou comme lien M3U) dans « J'ai un code » → l'app charge le bouquet de
   démonstration EMBARQUÉ (aucun réseau, aucune activation revendeur).
   Constante : `kReviewAccessCode` dans `lib/features/demo/data/demo_mode.dart`.
2. **Build Play sans paiement hors Store** (`--dart-define=PLAY_BUILD=true`) :
   plus AUCUN prix en €, essai gratuit, bouton d'achat ou lien vers le site
   marchand — `PricingBanner`, `PaywallBanner`, badge d'essai de l'accueil,
   CTA « Acheter » de l'écran bloquant, carte abonnement des réglages,
   diapo « essai gratuit » de l'onboarding. L'APK sideload GitHub garde tout.

## À faire dans la Play Console (Contenu de l'application → Identifiants)

- **Nom d'utilisateur** : `GPLAYREVIEW`
- **Mot de passe** : `GPLAYREVIEW` (le champ ne doit plus rester vide ;
  la valeur est ignorée par l'app mais Google exige un mot de passe)
- **Instructions** (en anglais) :

```
This app is an IPTV player. No account creation is needed.

To review all features without any subscription:
1. Open the app and complete the short onboarding.
2. On the home screen, tap "I have a code" (Xtream section).
3. Type GPLAYREVIEW in the Username field (any password) and confirm.
4. The app loads a built-in demonstration lineup (live channels and
   movies) that exercises the full player, categories, cinema and
   casting features. No server-side or reseller activation is required.

Alternatively, the "Demo mode" button on the empty home screen opens the
same demonstration lineup with one tap and no credentials.
```

- Si une **vraie ligne Xtream** est fournie en plus (recommandé pour la
  partie « chaînes réelles ») : la créer dans le panel avec ≥ 1 an
  d'expiration, ≥ 2 connexions, **sans verrou MAC** et **sans restriction
  de pays** (les relecteurs testent depuis les États-Unis), puis la
  vérifier soi-même : `http://<panel>/player_api.php?username=…&password=…`
  doit répondre `"auth":1` et `"status":"Active"`.

## Rappels avant renvoi

- Nouveau build AAB (nouveau `versionCode`) avec `PLAY_BUILD=true`.
- Renvoyer depuis la vue d'ensemble de la publication (pas d'appel).
- Les captures de la fiche doivent montrer l'app en fonctionnement
  (bouquet démo), jamais un simple habillage.
