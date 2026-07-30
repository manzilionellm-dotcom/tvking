/*
 * Expiration enforcer.
 *
 * Checking the subscription at connect time is not enforcement: a client that
 * connected one minute before expiry would keep the stream open for hours. So
 * the enforcer sweeps live sessions and cuts the ones whose device is no longer
 * entitled — expired, revoked, disabled or deleted.
 *
 * It re-evaluates entitlement from the database on every sweep rather than
 * trusting a timestamp captured at connect time, so a revocation or a deleted
 * device takes effect on the next tick too, not just a calendar expiry.
 */

import { systemClock, systemWallClock, type Clock, type WallClock } from "../clock.ts";
import type { EdgeProxy, SessionSnapshot } from "../edge.ts";
import type { AccessState, PortalRepository } from "./devices.ts";

export interface EnforcementEvent {
  type: "enforce-drop";
  device: number;
  label: string | null;
  reason: AccessState | "unknown-device";
  sessions: number;
}

export interface EnforcerOptions {
  repo: PortalRepository;
  edge: Pick<EdgeProxy, "sessions" | "dropSessions">;
  /** Sweep period. Shorter = tighter enforcement, more database reads. */
  intervalMs?: number;
  clock?: Clock;
  wallClock?: WallClock;
  onEvent?: (event: EnforcementEvent) => void;
}

export interface SweepResult {
  checkedSessions: number;
  droppedSessions: number;
  devices: Array<{ deviceId: number; reason: AccessState | "unknown-device"; sessions: number }>;
}

export class ExpirationEnforcer {
  #options: EnforcerOptions;
  #clock: Clock;
  #wallClock: WallClock;
  #running = false;
  #abort: AbortController | null = null;
  #loop: Promise<void> | null = null;
  #sweeps = 0;
  #dropped = 0;

  constructor(options: EnforcerOptions) {
    this.#options = options;
    this.#clock = options.clock ?? systemClock;
    this.#wallClock = options.wallClock ?? systemWallClock;
  }

  get running(): boolean {
    return this.#running;
  }

  get sweeps(): number {
    return this.#sweeps;
  }

  get droppedSessions(): number {
    return this.#dropped;
  }

  start(): void {
    if (this.#running) return;
    this.#running = true;
    this.#abort = new AbortController();
    this.#loop = this.#run(this.#abort.signal);
  }

  async stop(): Promise<void> {
    if (!this.#running) return;
    this.#running = false;
    this.#abort?.abort();
    this.#abort = null;
    await this.#loop?.catch(() => {});
    this.#loop = null;
  }

  /** One pass. Returns what it cut, so a test or an operator can see it. */
  sweep(): SweepResult {
    const now = this.#wallClock.now();
    const sessions = this.#options.edge.sessions().filter((s) => s.deviceId !== null);
    const result: SweepResult = { checkedSessions: sessions.length, droppedSessions: 0, devices: [] };

    const verdicts = new Map<number, AccessState | "unknown-device" | "ok">();
    for (const session of sessions) {
      const deviceId = session.deviceId as number;
      if (verdicts.has(deviceId)) continue;
      const device = this.#options.repo.device(deviceId);
      if (!device) {
        verdicts.set(deviceId, "unknown-device");
        continue;
      }
      const status = this.#options.repo.status(device, now);
      verdicts.set(deviceId, status.state === "active" ? "ok" : status.state);
    }

    for (const [deviceId, verdict] of verdicts) {
      if (verdict === "ok") continue;
      const affected = sessions.filter((s) => s.deviceId === deviceId).length;
      const dropped = this.#options.edge.dropSessions(
        (session: SessionSnapshot) => session.deviceId === deviceId,
        verdict
      );
      result.droppedSessions += dropped;
      result.devices.push({ deviceId, reason: verdict, sessions: dropped });
      this.#dropped += dropped;
      this.#options.onEvent?.({
        type: "enforce-drop",
        device: deviceId,
        label: this.#options.repo.device(deviceId)?.label ?? null,
        reason: verdict,
        sessions: dropped || affected,
      });
    }

    this.#sweeps += 1;
    return result;
  }

  async #run(signal: AbortSignal): Promise<void> {
    const intervalMs = this.#options.intervalMs ?? 15_000;
    while (!signal.aborted) {
      this.sweep();
      if (signal.aborted) return;
      await this.#clock.sleep(intervalMs, signal);
    }
  }
}
