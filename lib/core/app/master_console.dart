// =========================================================
//  master_console.dart — Drapeau du BUILD « Console maître »
// =========================================================
//  Certains builds sont destinés À TOI SEUL (l'exploitant) : une app à part,
//  qui s'ouvre DIRECTEMENT sur le générateur de tests (codes illimités, accès
//  complet 1 h) au lieu de l'accueil client.
//
//  Activé à la compilation :  flutter build ... --dart-define=MASTER_CONSOLE=true
//  (CI : workflow build-master). Par défaut FALSE → app cliente normale.
//
//  SÉCURITÉ : ce drapeau ne fait que changer l'UI de départ. Le POUVOIR réel
//  (envoyer des tests sans quota/paiement) reste verrouillé CÔTÉ SERVEUR sur
//  les MAC déclarées « maître » dans le panel. Un APK console volé est donc
//  inutile tant que sa MAC n'a pas été ajoutée par l'owner.
const bool kMasterConsole =
    bool.fromEnvironment('MASTER_CONSOLE', defaultValue: false);
