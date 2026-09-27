/**
 * Map customer S code → panel plan, and build /api/v1/activate payload.
 * Panel contract (admin-panel ActivatePage + cloudflare/api_v1 handleActivate):
 *   POST { mac: "MK:XX:XX:XX:XX:XX", plan: "yearly"|"lifetime", app_id?, customer_name? }
 */

export type PanelPlan = "yearly" | "lifetime";

const DEFAULT_WORKER_ACTIVATE =
  "https://app.7themotion.com/api/v1/activate";
const DEFAULT_APP_ID = "app_7motion";

/** Optional JSON map in ACTIVATION_S_CODES, e.g. {"ABC123":"yearly","XYZ":"lifetime"} */
function sCodeMapFromEnv(): Record<string, PanelPlan> {
  const raw = process.env.ACTIVATION_S_CODES?.trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    const out: Record<string, PanelPlan> = {};
    for (const [k, v] of Object.entries(parsed)) {
      const plan = normalizePlanToken(v);
      if (plan) out[k.trim().toUpperCase()] = plan;
    }
    return out;
  } catch {
    return {};
  }
}

export function normalizePlanToken(v: string): PanelPlan | null {
  const t = (v || "").trim().toLowerCase();
  if (!t) return null;
  if (/^(life|lifetime|vie|a[\s-]?vie|forever|15)$/.test(t)) return "lifetime";
  if (/^(year|yearly|annuel|an|1y|y1|9\.?99|999)$/.test(t)) return "yearly";
  if (t === "lifetime" || t === "yearly") return t;
  return null;
}

/**
 * Resolve S (activation code) → panel plan.
 * 1) ACTIVATION_S_CODES exact match
 * 2) Heuristic tokens inside the code (LIFE, YEAR, …)
 * 3) ACTIVATION_DEFAULT_PLAN (default yearly) when S is non-empty
 */
export function planFromSCode(sCode: string): PanelPlan | null {
  const s = (sCode || "").trim();
  if (!s) return null;

  const map = sCodeMapFromEnv();
  const hit = map[s.toUpperCase()];
  if (hit) return hit;

  const direct = normalizePlanToken(s);
  if (direct) return direct;

  const upper = s.toUpperCase();
  if (/LIFE|VIE|FOREVER|LIFETIME/.test(upper)) return "lifetime";
  if (/YEAR|ANNUEL|\bAN\b|YEARLY|1Y/.test(upper)) return "yearly";

  const def = normalizePlanToken(process.env.ACTIVATION_DEFAULT_PLAN || "yearly");
  return def;
}

export function activationApiUrl(): string {
  const fromEnv = process.env.ACTIVATION_API_URL?.replace(/\/$/, "");
  if (fromEnv) return fromEnv;
  return DEFAULT_WORKER_ACTIVATE;
}

export function activationApiKey(): string | undefined {
  return (
    process.env.ACTIVATION_API_KEY ||
    process.env.ACTIVATION_API_TOKEN ||
    undefined
  );
}

export function activationAdminSecret(): string | undefined {
  return (
    process.env.ACTIVATION_ADMIN_SECRET ||
    process.env.ADMIN_SECRET ||
    undefined
  );
}

export function panelActivateBody(mac: string, plan: PanelPlan) {
  return {
    mac,
    plan,
    app_id: process.env.ACTIVATION_APP_ID || DEFAULT_APP_ID,
  };
}

export function adminActionForPlan(plan: PanelPlan): "activate_year" | "activate_lifetime" {
  return plan === "lifetime" ? "activate_lifetime" : "activate_year";
}

export function workerOriginFromActivateUrl(url: string): string {
  try {
    const u = new URL(url);
    return u.origin;
  } catch {
    return "https://app.7themotion.com";
  }
}
