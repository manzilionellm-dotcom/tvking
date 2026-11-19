// =========================================================
//  paid_days_left.dart — Jours restants d'un abonnement payé
// =========================================================
//  La box reçoit la date de fin (`paidUntil`) avec son statut. On
//  l'affiche en jours sur l'accueil, et en couleur d'alerte la
//  dernière semaine : le client pense à renouveler AVANT la coupure.
//
//  Rien n'est inventé : pas de date (à vie, ou serveur muet) = `null`,
//  et l'accueil garde simplement « Abonnement actif ».
// =========================================================

const int _kDayMs = 24 * 60 * 60 * 1000;

/// À partir de combien de jours on passe en couleur d'alerte.
const int kPaidEndsSoonDays = 7;

/// Jours restants, arrondis au jour entamé (« il reste 2 h » = 1 jour).
/// `null` si aucune date n'est connue ou si elle est déjà passée.
int? paidDaysLeft({required int paidUntilMs, required int nowMs}) {
  if (paidUntilMs <= 0) return null;
  final int left = paidUntilMs - nowMs;
  if (left <= 0) return null;
  return (left / _kDayMs).ceil();
}

/// Vrai la dernière semaine.
bool paidEndsSoon(int? daysLeft) =>
    daysLeft != null && daysLeft <= kPaidEndsSoonDays;
