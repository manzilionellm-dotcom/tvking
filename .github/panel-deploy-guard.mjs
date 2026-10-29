// Refus fermé : un simple « DEPLOYER » ne suffit plus. Le gel reste actif
// tant que le propriétaire n'a pas fait revoir une modification du manifeste.
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function assertDeploymentAllowed(ctx) {
  if (ctx.event !== 'workflow_dispatch') throw new Error('Déploiement manuel obligatoire');
  if (ctx.actor !== 'manzilionellm-dotcom' || ctx.triggeringActor !== 'manzilionellm-dotcom') throw new Error('Déploiement réservé au propriétaire');
  if (ctx.ref !== 'refs/heads/claude/panel-mise-en-ligne') throw new Error('Branche de production obligatoire');
  if (ctx.confirmation !== 'DEPLOYER') throw new Error('Confirmation DEPLOYER obligatoire');
  if (ctx.mode !== 'reviewed') throw new Error('Panel gelé : déploiement bloqué');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const manifest = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'panel-production.json'), 'utf8'));
    assertDeploymentAllowed({
      event: process.env.GITHUB_EVENT_NAME, actor: process.env.GITHUB_ACTOR,
      triggeringActor: process.env.GITHUB_TRIGGERING_ACTOR, ref: process.env.GITHUB_REF,
      confirmation: process.env.PANEL_CONFIRMATION, mode: manifest.mode,
    });
    console.log('Autorisation du propriétaire vérifiée ; revue de l’environnement encore obligatoire');
  } catch (error) {
    const message = error instanceof SyntaxError ? 'Manifeste de production invalide' : error.message;
    console.error(`::error::${message}`);
    process.exitCode = 1;
  }
}

