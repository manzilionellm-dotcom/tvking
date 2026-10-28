// Aucun code de paquet démo ni format de quota n'est confirmé dans l'export.
// sub=99 a été refusé. Une simple variable d'environnement ne constitue PAS
// une preuve de gratuité et ne doit jamais ouvrir action=new par accident.
// Remplacer ce verrou uniquement avec le contrat officiel de ce fournisseur,
// des fixtures anonymisées et un contrôle AVANT création : tickets uniquement,
// durée 24 h, refus certain sans création et preuve de coût payant nul.
import { DemoUnavailable } from './gold_trial_policy.js';

export const demoContract = Object.freeze({
  verified: false,
  code: 'demo_contract_unverified',
  message: 'Le paquet démo de 24 h, son coût nul et les tickets disponibles restent à confirmer.',
});

export async function createVerifiedDemo24h() {
  // Pas de fetch, pas de déchiffrement de clé et pas de repli payant.
  throw new DemoUnavailable('demo_contract_unverified');
}
