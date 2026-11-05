// Refus fermé pour les clients. Les tests autorisés gardent leur canal séparé.
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

// Revue ponctuelle de l'APK Zuno : le gel commun reste actif. La preuve porte
// sur les objets Git réellement extraits, pas sur un nom d'app fourni en entrée.
function hasMatchingZunoTvReview(ctx) {
  const review = ctx.zunoTvReview;
  const sha = /^[0-9a-f]{40}$/;
  const workflow = 'manzilionellm-dotcom/tvking/.github/workflows/build-zuno-tv.yml@refs/heads/ccr-b93e1afd-gwirw0';
  if (!review || review.scope !== 'zuno-tv' || review.reviewedBy !== 'manzilionellm-dotcom' ||
      typeof review.reason !== 'string' || !review.reason.trim() ||
      !sha.test(review.sourceCommit ?? '') || !sha.test(review.androidTree ?? '') ||
      !sha.test(review.workflowBlob ?? '')) return false;
  const reviewedAt = Date.parse(review.reviewedAt);
  const expiresAt = Date.parse(review.expiresAt);
  const now = ctx.now ?? Date.now();
  if (![reviewedAt, expiresAt, now].every(Number.isFinite) ||
      reviewedAt > now || expiresAt <= now || expiresAt <= reviewedAt ||
      expiresAt - reviewedAt > 24 * 60 * 60 * 1000) return false;
  return ['build', 'client'].includes(ctx.operation) &&
    ctx.publish === 'true' && ctx.testBox === 'false' && ctx.playAab === 'false' &&
    ctx.variant === 'box' && ctx.backendUrl === '' &&
    ctx.workflowRef === workflow && sha.test(ctx.sourceSha ?? '') &&
    ctx.workflowSha === ctx.sourceSha && ctx.checkout?.head === ctx.sourceSha &&
    ctx.checkout?.androidTree === review.androidTree &&
    ctx.checkout?.workflowBlob === review.workflowBlob;
}

// Ces trois objets sont présents même avec fetch-depth: 1. Une erreur Git
// ferme cette autorisation ponctuelle ; elle ne désactive jamais le gel.
function readReviewCheckout() {
  try {
    const cwd = join(dirname(fileURLToPath(import.meta.url)), '..');
    const read = ref => execFileSync('git', ['rev-parse', '--verify', ref], {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    const dirty = execFileSync('git', ['status', '--porcelain', '--untracked-files=all',
      '--', 'android-app', '.github/workflows/build-zuno-tv.yml'], {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (dirty) return null;
    return { head: read('HEAD'), androidTree: read('HEAD:android-app'),
      workflowBlob: read('HEAD:.github/workflows/build-zuno-tv.yml') };
  } catch { return null; }
}

export function assertAppOperationAllowed(ctx) {
  if (ctx.repository !== 'manzilionellm-dotcom/tvking') throw new Error('Dépôt non autorisé');
  if (ctx.actor !== 'manzilionellm-dotcom' || ctx.triggeringActor !== 'manzilionellm-dotcom') {
    throw new Error('Action réservée au propriétaire, y compris les relances');
  }
  if (!['frozen', 'reviewed'].includes(ctx.mode)) throw new Error('Manifeste apps absent ou invalide');
  if (!['build', 'test', 'client', 'cleanup'].includes(ctx.operation)) throw new Error('Opération inconnue');

  if (ctx.event === 'pull_request') {
    const pr = ctx.pr;
    if (!pr || pr.user?.login !== 'manzilionellm-dotcom' ||
        pr.head?.repo?.full_name !== ctx.repository ||
        pr.head?.ref !== 'ccr-b93e1afd-gwirw0' ||
        pr.base?.ref !== 'ccr-sport-preuve-20261008' ||
        !['build', 'test'].includes(ctx.operation) ||
        ctx.publish !== 'false' || ctx.testBox !== 'true' ||
        ctx.playAab !== 'false' || ctx.backendUrl !== '' || ctx.variant !== 'box') {
      throw new Error('PR non autorisée pour un build signé ou une publication');
    }
    return;
  }

  // Un push peut compiler sans publier ; les tests restent dans un workflow distinct.
  if (ctx.event === 'push' && ctx.operation === 'build' && ctx.publish !== 'true' && ctx.testBox !== 'true') return;
  if (ctx.event !== 'workflow_dispatch' || ctx.ref !== 'refs/heads/ccr-b93e1afd-gwirw0') {
    throw new Error('Lancement manuel sur la branche de travail obligatoire');
  }
  if (ctx.operation === 'test' || (ctx.operation === 'build' && ctx.testBox === 'true')) {
    if (ctx.publish !== 'false') throw new Error('Un test exige publish=false');
    return;
  }
  if (ctx.operation === 'build' && ctx.publish !== 'true') return;
  if (ctx.mode !== 'reviewed' && !hasMatchingZunoTvReview(ctx)) {
    throw new Error('Apps clients gelées : publication ou suppression bloquée');
  }
  const expected = ctx.operation === 'cleanup' ? 'NETTOYER_RELEASES' : 'PUBLIER_APP';
  if (ctx.confirmation !== expected) throw new Error('Confirmation explicite du propriétaire obligatoire');
}

export function appEnvironmentContext(operation = process.env.APP_OPERATION || 'build') {
    const manifest = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'app-production.json'), 'utf8'));
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const input = event.inputs || {};
    return {
      repository: process.env.GITHUB_REPOSITORY,
      actor: process.env.GITHUB_ACTOR, triggeringActor: process.env.GITHUB_TRIGGERING_ACTOR,
      ref: process.env.GITHUB_REF, event: process.env.GITHUB_EVENT_NAME, pr: event.pull_request,
      operation, mode: manifest.mode,
      zunoTvReview: manifest.zunoTvReview,
      workflowRef: process.env.GITHUB_WORKFLOW_REF,
      workflowSha: process.env.GITHUB_WORKFLOW_SHA,
      sourceSha: process.env.GITHUB_SHA,
      checkout: manifest.zunoTvReview ? readReviewCheckout() : null,
      publish: process.env.APP_PUBLISH ?? input.publish ?? 'false',
      testBox: process.env.APP_TEST_BOX ?? input.test_box ?? 'false',
      playAab: process.env.APP_PLAY_AAB ?? input.play_aab ?? 'false',
      backendUrl: process.env.APP_BACKEND_URL ?? input.backend_url ?? '',
      variant: process.env.APP_VARIANT ?? input.variante ?? 'box',
      confirmation: process.env.APP_CONFIRMATION ?? input.confirme ?? '',
    };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    assertAppOperationAllowed(appEnvironmentContext());
    console.log('Autorisation apps vérifiée, aucun secret affiché');
  } catch {
    // Ne jamais recopier un corps d'événement, une entrée ou une exception brute.
    console.error('::error::Action apps refusée : vérifier propriétaire, branche, canal et gel');
    process.exitCode = 1;
  }
}

