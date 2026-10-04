// =========================================================
//  display_mac.dart — La MAC telle que le CLIENT la voit
// =========================================================
//  L'identifiant interne de la box est « MK:AD:A6:98:70:6A » : c'est
//  la clé du serveur, des appels réseau et du QR « Mon espace ». On
//  ne le change pas.
//
//  À l'écran (et dans le message WhatsApp pré-rempli), le client voit
//  seulement « AD:A6:98:70:6A » : plus court à dicter, et le panel
//  remet « MK: » tout seul quand le revendeur le tape.
//
//  Fonction PURE : pas de Flutter, pas de préférence. L'écran passe
//  le réglage de repli (RepairFlags.macShowPrefix) en paramètre.
// =========================================================

/// Retire le préfixe « MK: » (casse ignorée, espaces autour retirés).
/// Une valeur sans préfixe, vide ou « … » (pas encore chargée) est
/// rendue telle quelle. [showPrefix] vrai = ancien affichage, inchangé.
String displayMac(String mac, {bool showPrefix = false}) {
  if (showPrefix) return mac;
  final String t = mac.trim();
  if (t.length > 3 && t.substring(0, 3).toUpperCase() == 'MK:') {
    return t.substring(3);
  }
  return mac;
}
