// Constat fourni par le propriétaire le 29 octobre 2026 : le formulaire web
// « 1 Day / Price: Free » consomme un ticket démo, aucun crédit payant.
// Cela ne prouve aucun appel API : v1.81 accepte sub=1,3,6,12, refuse sub=99
// et ne propose pas de lecture des tickets démo. Aucun paramètre à deviner.
// Garder ce verrou fermé jusqu'à confirmation ÉCRITE de Strong de l'appel
// exact de création d'une démo de 24 h. Un interrupteur ou READY ne suffit pas.
import { DemoUnavailable } from './gold_trial_policy.js';

export const demoContract = Object.freeze({
  verified: false,
  code: 'demo_contract_unverified',
  message: 'Essais automatiques fermés : confirmation écrite de Strong attendue pour l’appel API exact de démo 24 h.',
});

export async function createVerifiedDemo24h() {
  // Pas de fetch, pas de déchiffrement de clé et pas de repli payant.
  throw new DemoUnavailable('demo_contract_unverified');
}
