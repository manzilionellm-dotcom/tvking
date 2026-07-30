/*
 * Subscription durations.
 *
 * Months are calendar months, not "30 days": a subscriber who buys three months
 * on 15 March expects 15 June, and an operator comparing a panel with an invoice
 * expects the same. Day-of-month is clamped, so 31 January + 1 month is 28 (or
 * 29) February rather than spilling into March.
 *
 * All arithmetic is UTC. Local time would make an expiry move when the server's
 * timezone or DST changes — an account that dies an hour early is a support
 * ticket nobody can reproduce.
 */

export type PlanId = "trial-24h" | "1m" | "3m" | "6m" | "12m";

export interface Plan {
  id: PlanId;
  label: string;
  /** Fixed duration in hours (trials), or calendar months. Exactly one is set. */
  hours?: number;
  months?: number;
  trial: boolean;
}

export const PLANS: Record<PlanId, Plan> = {
  "trial-24h": { id: "trial-24h", label: "Essai 24 h", hours: 24, trial: true },
  "1m": { id: "1m", label: "1 mois", months: 1, trial: false },
  "3m": { id: "3m", label: "3 mois", months: 3, trial: false },
  "6m": { id: "6m", label: "6 mois", months: 6, trial: false },
  "12m": { id: "12m", label: "12 mois", months: 12, trial: false },
};

export const PLAN_IDS = Object.keys(PLANS) as PlanId[];

export function isPlanId(value: unknown): value is PlanId {
  return typeof value === "string" && Object.prototype.hasOwnProperty.call(PLANS, value);
}

/** Adds calendar months in UTC, clamping the day to the target month's length. */
export function addMonthsUtc(epochMs: number, months: number): number {
  const date = new Date(epochMs);
  const day = date.getUTCDate();
  const target = new Date(epochMs);
  target.setUTCDate(1); // avoid rolling over while changing the month
  target.setUTCMonth(target.getUTCMonth() + months);
  const daysInTarget = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)
  ).getUTCDate();
  target.setUTCDate(Math.min(day, daysInTarget));
  return target.getTime();
}

/** When a plan bought at `startsAt` runs out. */
export function planExpiry(plan: PlanId, startsAt: number): number {
  const definition = PLANS[plan];
  if (definition.hours !== undefined) return startsAt + definition.hours * 3_600_000;
  return addMonthsUtc(startsAt, definition.months ?? 0);
}

/**
 * Extending a still-valid subscription adds to what is left rather than
 * restarting from today — renewing early must never cost the subscriber days.
 */
export function renewalStart(currentExpiry: number | null, now: number): number {
  return currentExpiry !== null && currentExpiry > now ? currentExpiry : now;
}

export function formatRemaining(ms: number): string {
  if (ms <= 0) return "expiré";
  const minutes = Math.floor(ms / 60_000);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  if (days > 0) return `${days} j ${hours} h`;
  if (hours > 0) return `${hours} h ${minutes % 60} min`;
  return `${minutes} min`;
}
