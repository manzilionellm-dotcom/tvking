// =========================================================
//  activation.ts — UN seul catalogue de durées pour tout le panel
// =========================================================
//  Avant le 06/10/2026, trois écrans proposaient trois listes différentes :
//    • « Grande activation… »   : 1 an, à vie (+ bloc « jours d'essai » 3/7/14/30) ;
//    • « Activation à distance » : essai 3 j / 7 j / 1 mois, 1 an, à vie ;
//    • fiche appareil            : 1, 3, 6 mois, 1 an, à vie.
//  Le même geste (activer une box) avait donc trois réponses. Ce fichier est
//  désormais la seule source : l'écran « Activer une box » et la fenêtre
//  « Activer / prolonger » de la fiche appareil lisent tous deux ce catalogue.
//
//  Identifiants = ceux que le Worker comprend (cloudflare/api_v1.js,
//  planToDays) : `trial_<N>d` = N jours d'essai GRATUITS (0 crédit, même pour
//  un revendeur), `monthly` 30 j, `quarterly` 90 j, `biannual` 180 j,
//  `yearly` 365 j, `lifetime` sans fin.
//  Les essais s'écrivent en jours (« 30 j ») et les abonnements en mois :
//  jamais deux boutons « 1 mois » qui ne veulent pas dire la même chose.
// =========================================================

export type PlanOption = { id: string; label: string };

/// Essais gratuits.
export const TRIAL_PLANS: PlanOption[] = [
  { id: 'trial_3d', label: '3 j' },
  { id: 'trial_7d', label: '7 j' },
  { id: 'trial_14d', label: '14 j' },
  { id: 'trial_30d', label: '30 j' },
];

/// Abonnements payés (crédits débités pour un revendeur).
export const PAID_PLANS: PlanOption[] = [
  { id: 'monthly', label: '1 mois' },
  { id: 'quarterly', label: '3 mois' },
  { id: 'biannual', label: '6 mois' },
  { id: 'yearly', label: '1 an' },
  { id: 'lifetime', label: 'À vie' },
];

/// Choix par défaut d'une activation neuve : 7 jours d'essai. Un oubli ne
/// coûte aucun crédit (décision du 05/10/2026, commit 636aad6).
export const DEFAULT_PLAN = 'trial_7d';

/// Choix par défaut pour prolonger une box qui a déjà un abonnement.
export const DEFAULT_RENEW_PLAN = 'yearly';

export function isTrialPlan(plan: string): boolean {
  return plan.startsWith('trial');
}

export function planLabel(plan: string): string {
  const hit = [...TRIAL_PLANS, ...PAID_PLANS].find((p) => p.id === plan);
  if (!hit) return plan;
  return isTrialPlan(plan) ? `Essai ${hit.label}` : hit.label;
}

/// Coût en crédits d'une durée : 0 pour un essai, sinon le tarif du panel
/// (`plan_costs`), `null` s'il n'est pas connu (on n'affiche alors rien).
export function planCost(plan: string, costs: { plan: string; credits: number }[]): number | null {
  if (isTrialPlan(plan)) return 0;
  const row = costs.find((c) => c.plan === plan);
  return row ? row.credits : null;
}

/// Phrase de résultat après une activation réussie.
export function activationResultText(
  plan: string,
  result: { plan?: string | null; expires_at?: number | null },
  formatDate: (ms: number) => string,
): string {
  if (result.plan === 'lifetime' || result.expires_at == null) return 'Activée à vie.';
  const until = formatDate(result.expires_at);
  return isTrialPlan(plan) ? `Essai gratuit jusqu’au ${until}.` : `Activée jusqu’au ${until}.`;
}

/// Texte du bouton : le prix est dit AVANT le clic.
export function activateButtonText(plan: string, cost: number | null, isReseller: boolean): string {
  if (isTrialPlan(plan)) return 'Activer · essai gratuit';
  if (isReseller && cost !== null) return `Activer · ${cost} crédit${cost > 1 ? 's' : ''}`;
  return 'Activer';
}
