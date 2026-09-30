// =========================================================
//  activation_hint.dart — Phrase affichée quand ça ne s'ouvre pas
// =========================================================
//  Trois cas que l'écran ne doit plus confondre avec une recherche
//  sans fin : pas de réseau, code pas activé, compte gelé ou bloqué.
// =========================================================

/// `syncHint` vient de SubscriptionState : offline, expired, frozen,
/// banned, ou null.
String? activationHintFr(String? syncHint) {
  switch (syncHint) {
    case 'offline':
      return 'Pas de réseau. La vérification n\'a pas abouti.';
    case 'expired':
      return 'Le code de cette box n\'est pas activé.';
    case 'frozen':
      return 'Ce compte est gelé. Contacte ton revendeur.';
    case 'banned':
      return 'Ce compte est bloqué.';
    default:
      return null;
  }
}
