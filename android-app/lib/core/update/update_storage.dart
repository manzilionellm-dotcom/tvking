// =========================================================
//  update_storage.dart — La box a-t-elle la place d'installer ?
// =========================================================
//  Constaté le 13/11/2026 sur une box avec 710 Mo libres : Android
//  affiche seulement « Application non installée », sans dire que
//  c'est la place qui manque. On a perdu une demi-journée à chercher
//  ailleurs.
//
//  Zuno ne peut pas savoir ce que l'installateur Android va décider
//  (chaque box a son propre seuil). Donc on ne BLOQUE jamais la mise
//  à jour : on prévient, avec le chiffre, et un deuxième OK continue.
// =========================================================

/// Marge que le système garde pour lui : en dessous, beaucoup de box
/// refusent toute installation.
const int kUpdateSystemReserveBytes = 1024 * 1024 * 1024; // 1 Go

/// Vrai si l'installation risque d'être refusée faute de place.
///
/// Il faut la place du fichier téléchargé, de sa copie installée et
/// des bibliothèques dépliées : on compte 3 fois la taille de l'APK,
/// plus la marge du système. [freeBytes] négatif = mesure impossible :
/// on ne dérange pas le client pour un doute.
bool updateStorageIsTight({required int freeBytes, required int apkBytes}) {
  if (freeBytes < 0 || apkBytes <= 0) return false;
  return freeBytes < apkBytes * 3 + kUpdateSystemReserveBytes;
}

/// Octets → Mo entiers, pour l'affichage (« 710 Mo libres »).
int updateFreeMegabytes(int freeBytes) =>
    freeBytes <= 0 ? 0 : freeBytes ~/ (1024 * 1024);
