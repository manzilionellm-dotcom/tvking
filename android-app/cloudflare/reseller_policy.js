// Central SQL constraints also protect non-/activate paths (families, renew).
const ready = new WeakSet();
export async function policySchema(env) {
  if (ready.has(env.DB)) return;
  await env.DB.prepare("CREATE TABLE IF NOT EXISTS reseller_limits (reseller_id TEXT PRIMARY KEY, max_activations INTEGER, allowed_plans TEXT NOT NULL DEFAULT '[\"yearly\",\"lifetime\",\"trial\",\"trial_2h\",\"trial_24h\",\"trial_3d\",\"trial_7d\",\"trial_30d\"]', expires_at INTEGER, max_sub_resellers INTEGER NOT NULL DEFAULT 0)").run();
  const check = `
    SELECT CASE WHEN EXISTS (SELECT 1 FROM reseller_limits r WHERE r.reseller_id=NEW.reseller_id AND r.expires_at IS NOT NULL AND r.expires_at <= unixepoch()*1000) THEN RAISE(ABORT, 'reseller_expired') END;
    SELECT CASE WHEN EXISTS (SELECT 1 FROM reseller_limits r WHERE r.reseller_id=NEW.reseller_id AND NOT EXISTS(SELECT 1 FROM json_each(r.allowed_plans) WHERE value=NEW.plan)) THEN RAISE(ABORT, 'reseller_plan_limit') END;
    SELECT CASE WHEN EXISTS (SELECT 1 FROM reseller_limits r WHERE r.reseller_id=NEW.reseller_id AND r.max_activations IS NOT NULL AND (SELECT COUNT(*) FROM licenses l WHERE l.reseller_id=NEW.reseller_id AND l.status='active' AND (l.expires_at IS NULL OR l.expires_at > unixepoch()*1000) AND l.id!=NEW.id) >= r.max_activations) THEN RAISE(ABORT, 'reseller_activation_limit') END;
  `;
  await env.DB.batch([
    env.DB.prepare(`CREATE TRIGGER IF NOT EXISTS reseller_limit_insert BEFORE INSERT ON licenses WHEN NEW.reseller_id IS NOT NULL AND NEW.status='active' BEGIN ${check} END`),
    env.DB.prepare(`CREATE TRIGGER IF NOT EXISTS reseller_limit_update BEFORE UPDATE ON licenses WHEN NEW.reseller_id IS NOT NULL AND NEW.status='active' BEGIN ${check} END`),
    env.DB.prepare(`CREATE TRIGGER IF NOT EXISTS reseller_limit_children BEFORE INSERT ON resellers WHEN NEW.parent_reseller_id IS NOT NULL BEGIN SELECT CASE WHEN (SELECT COUNT(*) FROM resellers WHERE parent_reseller_id=NEW.parent_reseller_id) >= COALESCE((SELECT max_sub_resellers FROM reseller_limits WHERE reseller_id=NEW.parent_reseller_id),0) THEN RAISE(ABORT,'reseller_child_limit') END; END`),
  ]);
  ready.add(env.DB);
}
const PLANS = new Set(['monthly','quarterly','biannual','yearly','lifetime','custom','trial','trial_2h','trial_24h','trial_3d','trial_7d','trial_30d']);
export function parsePolicy(body) {
  const max = body.max_activations == null ? null : body.max_activations;
  const expiry = body.expires_at == null ? null : body.expires_at;
  const children = body.max_sub_resellers ?? 0;
  if ((max !== null && (!Number.isSafeInteger(max) || max < 0 || max > 1000000)) ||
      (expiry !== null && (!Number.isSafeInteger(expiry) || expiry < 0)) ||
      !Number.isSafeInteger(children) || children < 0 || children > 1000 ||
      !Array.isArray(body.allowed_plans) || body.allowed_plans.length > PLANS.size || body.allowed_plans.some(x => !PLANS.has(x))) return null;
  return { max_activations: max, expires_at: expiry, max_sub_resellers: children, allowed_plans: [...new Set(body.allowed_plans)] };
}
export async function getPolicy(env, id) {
  await policySchema(env);
  const row = await env.DB.prepare('SELECT * FROM reseller_limits WHERE reseller_id=?').bind(id).first();
  return row ? { ...row, allowed_plans: JSON.parse(row.allowed_plans) } : { reseller_id: id, max_activations: null, expires_at: null, max_sub_resellers: 0, allowed_plans: ['yearly','lifetime','trial','trial_2h','trial_24h','trial_3d','trial_7d','trial_30d'] };
}
export async function savePolicy(env, id, policy) {
  await policySchema(env);
  await env.DB.prepare('INSERT INTO reseller_limits (reseller_id, max_activations, allowed_plans, expires_at, max_sub_resellers) VALUES (?,?,?,?,?) ON CONFLICT(reseller_id) DO UPDATE SET max_activations=excluded.max_activations, allowed_plans=excluded.allowed_plans, expires_at=excluded.expires_at, max_sub_resellers=excluded.max_sub_resellers').bind(id, policy.max_activations, JSON.stringify(policy.allowed_plans), policy.expires_at, policy.max_sub_resellers).run();
}
