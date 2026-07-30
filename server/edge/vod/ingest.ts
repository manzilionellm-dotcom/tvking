/*
 * Background VOD ingestion.
 *
 * Walks every enabled source on a timer, downloads its playlist through the
 * account's connection budget (see `EdgeProxy.fetchText` — a catalogue refresh
 * is an upstream connection like any other and must not become the second one),
 * keeps only the lines that look like VOD, and folds them into the catalogue.
 *
 * A source that fails does not stop the run and does not blank its catalogue:
 * the error is recorded against that source and the previous items stay
 * playable. An empty library is a worse outage than a stale one.
 */

import { parseM3u } from "../m3u.ts";
import { systemClock, type Clock } from "../clock.ts";
import { looksLikeVod } from "./classify.ts";
import type { IngestOutcome, VodCatalog } from "./catalog.ts";

export interface IngestReport {
  source: string;
  sourceId: number;
  ok: boolean;
  skipped?: "busy" | "disabled";
  error?: string;
  entries?: number;
  outcome?: IngestOutcome;
  durationMs: number;
}

export type IngestEvent =
  | { type: "ingest-start"; source: string }
  | { type: "ingest-done"; source: string; titles: number; streams: number; durationMs: number }
  | { type: "ingest-skip"; source: string; reason: string }
  | { type: "ingest-error"; source: string; message: string };

export interface IngestWorkerOptions {
  catalog: VodCatalog;
  /** Downloads a playlist within the account's connection budget. */
  fetchPlaylist: (accountId: string, url: string, signal?: AbortSignal) => Promise<string>;
  /** How often to sweep every source. */
  intervalMs?: number;
  clock?: Clock;
  onEvent?: (event: IngestEvent) => void;
}

export class VodIngestWorker {
  #options: IngestWorkerOptions;
  #clock: Clock;
  #running = false;
  #abort: AbortController | null = null;
  #loop: Promise<void> | null = null;
  #lastRunAt = 0;
  #runs = 0;

  constructor(options: IngestWorkerOptions) {
    this.#options = options;
    this.#clock = options.clock ?? systemClock;
  }

  get running(): boolean {
    return this.#running;
  }

  get runs(): number {
    return this.#runs;
  }

  get lastRunAt(): number {
    return this.#lastRunAt;
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

  /** One pass over every source (or a single one). Safe to call by hand. */
  async runOnce(options: { sourceId?: number; signal?: AbortSignal } = {}): Promise<IngestReport[]> {
    const sources = this.#options.catalog
      .listSources()
      .filter((source) => options.sourceId === undefined || source.id === options.sourceId);

    const reports: IngestReport[] = [];
    for (const source of sources) {
      if (options.signal?.aborted) break;
      const startedAt = this.#clock.now();

      if (!source.enabled) {
        reports.push({
          source: source.name,
          sourceId: source.id,
          ok: true,
          skipped: "disabled",
          durationMs: 0,
        });
        continue;
      }

      this.#emit({ type: "ingest-start", source: source.name });
      try {
        const body = await this.#options.fetchPlaylist(source.accountId, source.url, options.signal);
        const playlist = parseM3u(body);
        const entries = playlist.entries.filter((entry) =>
          looksLikeVod({ url: entry.url, group: entry.group, name: entry.name })
        );
        const outcome = this.#options.catalog.ingest(source.id, entries);
        this.#options.catalog.markIngest(source.id, { items: entries.length, error: null });

        const durationMs = this.#clock.now() - startedAt;
        reports.push({
          source: source.name,
          sourceId: source.id,
          ok: true,
          entries: entries.length,
          outcome,
          durationMs,
        });
        this.#emit({
          type: "ingest-done",
          source: source.name,
          titles: outcome.titlesCreated,
          streams: outcome.streamsCreated,
          durationMs,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const busy = /busy streaming/.test(message);
        // Busy is not a failure: the account was serving a viewer, which
        // outranks a catalogue refresh. Try again next cycle.
        if (!busy) this.#options.catalog.markIngest(source.id, { items: 0, error: message });
        reports.push({
          source: source.name,
          sourceId: source.id,
          ok: false,
          skipped: busy ? "busy" : undefined,
          error: message,
          durationMs: this.#clock.now() - startedAt,
        });
        this.#emit(
          busy
            ? { type: "ingest-skip", source: source.name, reason: "account busy" }
            : { type: "ingest-error", source: source.name, message }
        );
      }
    }

    this.#runs += 1;
    this.#lastRunAt = this.#clock.now();
    return reports;
  }

  async #run(signal: AbortSignal): Promise<void> {
    const intervalMs = this.#options.intervalMs ?? 6 * 3_600_000;
    while (!signal.aborted) {
      await this.runOnce({ signal });
      if (signal.aborted) return;
      await this.#clock.sleep(intervalMs, signal);
    }
  }

  #emit(event: IngestEvent): void {
    this.#options.onEvent?.(event);
  }
}
