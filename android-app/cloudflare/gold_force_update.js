import { observeDatabase, strictConfigRead } from './gold_config_reads.js';
import { publishedRelease } from './gold_published_release.js';

const platformOf = request => new URL(request.url).searchParams.get('platform') === 'tv' ? 'tv' : 'mobile';
const integer = value => Number.isSafeInteger(value) && value > 0 ? value : 0;
function replace(response, value, status = response.status) {
  const headers = new Headers(response.headers);
  headers.delete('Content-Length'); headers.set('Cache-Control', 'no-store');
  return new Response(JSON.stringify(value), { status, headers });
}

async function attachVersion(response, release) {
  if (!response.ok) return response;
  const value = await response.clone().json();
  const stored = integer(value.minBuildTs);
  const canApply = release.canForce && stored <= release.versionCode;
  return replace(response, { ...value,
    configuredMinBuildTs: stored,
    minBuildTs: canApply ? stored : 0,
    observedLatestBuildTs: integer(value.latestBuildTs),
    latestBuildTs: release.versionCode,
    publishedBuildTs: release.versionCode,
    canForce: release.canForce,
    blockedReason: release.blockedReason,
    publicationCheckedAt: release.checkedAt,
    publicationSource: release.source,
  });
}

export function createForceUpdateRoutes({ original, notify }) {
  return async (request, env, ctx) => {
    const url = new URL(request.url);
    const publicRoute = url.pathname === '/api/app-version';
    const adminRoute = url.pathname === '/api/v1/force-update';
    if (!publicRoute && !adminRoute) return null;
    const platform = platformOf(request);
    if (request.method === 'GET') {
      // Le build déclaré par n'importe quel client est une observation, jamais
      // la preuve qu'un APK compatible peut être téléchargé. Le GET public
      // ne peut plus relever latest_build_ts avec un numéro arbitraire.
      url.searchParams.delete('build');
      const read = new Request(url, { method: 'GET', headers: request.headers });
      const response = await strictConfigRead(env, observed => original.fetch(read, observed, ctx));
      // L'auth propriétaire originale est évaluée avant tout appel GitHub.
      if (!response.ok) return response;
      return attachVersion(response, await publishedRelease(platform));
    }
    if (!adminRoute || request.method !== 'POST') return null;
    const body = await request.clone().json().catch(() => null);
    if (body?.action !== 'force') {
      // Désactiver reste possible même si GitHub est indisponible. L'original
      // conserve ses validations, son audit et ses droits propriétaires.
      const response = await original.fetch(request, env, ctx);
      if (response.ok) ctx.waitUntil(notify(env, 'force_update'));
      return response;
    }
    const authRead = new Request(url, { method: 'GET', headers: request.headers });
    const authorized = await strictConfigRead(env, observed => original.fetch(authRead, observed, ctx));
    if (!authorized.ok) return authorized;
    const release = await publishedRelease(platform, { fresh: true });
    if (!release.canForce) return replace(authorized, {
      error: 'published_release_unverified', canForce: false,
      publishedBuildTs: 0, blockedReason: release.blockedReason,
      message: 'Aucun APK client publié et téléchargeable n’a pu être vérifié. La mise à jour forcée reste désactivée.',
    }, 409);
    const latestKey = `latest_build_ts${platform === 'tv' ? '_tv' : ''}`;
    // Dans CET appel uniquement, l'original lit la version réellement publiée
    // au lieu du build autoannoncé. Il continue à vérifier le propriétaire et
    // à écrire/auditer lui-même min_build_ts ; aucun latest global n'est forgé.
    const DB = observeDatabase(env.DB, { firstOverride: (sql, args, columns) => {
      if (/^SELECT value FROM app_config WHERE key = \?$/i.test(sql.trim()) && args[0] === latestKey) {
        return columns[0] === 'value' ? String(release.versionCode) : { value: String(release.versionCode) };
      }
      return undefined;
    } });
    const response = await original.fetch(request, { ...env, DB }, ctx);
    if (response.ok) ctx.waitUntil(notify(env, 'force_update'));
    return attachVersion(response, release);
  };
}
