// Valider l'ensemble des tags avant toute suppression, sans interpolation shell.
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { appEnvironmentContext, assertAppOperationAllowed } from './app-release-guard.mjs';

export function cleanupTags(raw) {
  if (typeof raw !== 'string' || raw.length > 1000) throw new Error('Liste de tags invalide');
  const tags = [...new Set(raw.trim().split(/\s+/).filter(Boolean))];
  if (tags.length === 0 || tags.length > 20) throw new Error('Entre un et vingt anciens tags obligatoires');
  // Seuls les anciens builds numérotés sont nettoyables. Tous les canaux actifs
  // (clients ET tests) sont ainsi exclus, même s'ils sont ajoutés à l'avenir.
  if (tags.some((tag) => !/^(?:build|cast)-[0-9]{1,10}$/.test(tag))) {
    throw new Error('Tag protégé ou format non autorisé ; aucune suppression');
  }
  return tags;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    // La protection s'applique aussi si un autre workflow appelle ce script.
    assertAppOperationAllowed(appEnvironmentContext('cleanup'));
    const tags = cleanupTags(process.env.CLEANUP_TAGS);
    if (process.env.GITHUB_REPOSITORY !== 'manzilionellm-dotcom/tvking') throw new Error('Dépôt non autorisé');
    for (const tag of tags) {
      const result = spawnSync('gh', ['release', 'delete', tag, '--repo', process.env.GITHUB_REPOSITORY, '--yes', '--cleanup-tag'], { stdio: 'inherit', shell: false });
      if (result.error || result.status !== 0) throw new Error('Suppression refusée ; arrêt au premier échec');
    }
  } catch {
    console.error('::error::Nettoyage refusé ou interrompu ; aucun succès supposé');
    process.exitCode = 1;
  }
}
