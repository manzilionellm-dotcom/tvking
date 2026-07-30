/*
 * On-demand import and download — the two things the "Télécharger" buttons do.
 *
 * Nothing here runs on a timer. Adding a source registers a provider line and
 * stops; pulling its catalogue is a separate, explicit act, and so is fetching
 * an individual film. That is the whole point of the rewrite: a background
 * worker that scrapes providers on a schedule spends WAN bandwidth and slot
 * time on content nobody asked for, and leaves an operator arguing with a
 * catalogue that keeps changing under them.
 *
 * Both actions still go through the account's connection budget: an import or a
 * download is an upstream connection like any other, and must never become the
 * second one or interrupt a viewer.
 */

import { createWriteStream } from "node:fs";
import { mkdir, rename, rm, stat } from "node:fs/promises";
import path from "node:path";
import { parseM3u } from "../m3u.ts";
import { looksLikeVod } from "./classify.ts";
import { UpstreamError, type OriginTransport } from "../origin.ts";
import { assertMirrorsMasterSignature, masterSignature, type UpstreamIdentity } from "../sanitize.ts";
import type { SlotLease } from "../slots.ts";
import type { VodItem, VodLibrary } from "./library.ts";

export interface ImportReport {
  sourceId: number;
  source: string;
  ok: boolean;
  /** Lines that looked like VOD. */
  entries: number;
  created: number;
  updated: number;
  error?: string;
  durationMs: number;
}

export interface DownloadReport {
  itemId: number;
  ok: boolean;
  bytes: number;
  resumedFrom: number;
  path?: string;
  error?: string;
  durationMs: number;
  cancelled?: boolean;
}

export type DownloadEvent =
  | { type: "vod-import"; source: string; entries: number; created: number }
  | { type: "vod-import-failed"; source: string; message: string }
  | { type: "vod-download-start"; item: number; title: string }
  | { type: "vod-download-done"; item: number; title: string; bytes: number }
  | { type: "vod-download-failed"; item: number; title: string; message: string }
  | { type: "vod-download-cancelled"; item: number; title: string };

export interface DownloaderOptions {
  library: VodLibrary;
  transport: OriginTransport;
  /** Where downloaded media lives. One file per item. */
  dir: string;
  /** Master signature of the account a source belongs to. */
  identityFor: (accountId: string) => UpstreamIdentity;
  /** Connection budget hook; null means "the account is busy streaming". */
  acquireLease?: (accountId: string) => Promise<SlotLease | null>;
  /** Downloads a playlist through the same budget. */
  fetchPlaylist: (accountId: string, url: string, signal?: AbortSignal) => Promise<string>;
  /** Refuse a file larger than this (0 = no limit). */
  maxFileBytes?: number;
  /** How often progress is written to the database, in bytes. */
  progressEveryBytes?: number;
  now?: () => number;
  onEvent?: (event: DownloadEvent) => void;
}

const SAFE_EXT = /^[a-z0-9]{1,5}$/i;

export class VodDownloader {
  #options: DownloaderOptions;
  #running = new Map<number, AbortController>();

  constructor(options: DownloaderOptions) {
    this.#options = options;
  }

  /** Item ids being downloaded right now. */
  get active(): number[] {
    return [...this.#running.keys()];
  }

  isDownloading(itemId: number): boolean {
    return this.#running.has(itemId);
  }

  /**
   * "Télécharger" on a source: fetch its playlist once, keep the VOD lines, and
   * register them. Media files are NOT fetched here — an operator picks those.
   */
  async importSource(sourceId: number, options: { signal?: AbortSignal } = {}): Promise<ImportReport> {
    const library = this.#options.library;
    const source = library.source(sourceId);
    if (!source) throw new UpstreamError(`unknown VOD source ${sourceId}`, 404);

    const startedAt = this.#now();
    try {
      const body = await this.#options.fetchPlaylist(source.accountId, source.url, options.signal);
      const playlist = parseM3u(body);
      const entries = playlist.entries.filter((entry) =>
        looksLikeVod({ url: entry.url, group: entry.group, name: entry.name })
      );

      let created = 0;
      let updated = 0;
      for (const entry of entries) {
        const result = library.registerItem(sourceId, entry);
        if (result.created) created += 1;
        else updated += 1;
      }
      library.markImport(sourceId, { items: entries.length, error: null });
      this.#emit({ type: "vod-import", source: source.name, entries: entries.length, created });

      return {
        sourceId,
        source: source.name,
        ok: true,
        entries: entries.length,
        created,
        updated,
        durationMs: this.#now() - startedAt,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      library.markImport(sourceId, { items: 0, error: message });
      this.#emit({ type: "vod-import-failed", source: source.name, message });
      return {
        sourceId,
        source: source.name,
        ok: false,
        entries: 0,
        created: 0,
        updated: 0,
        error: message,
        durationMs: this.#now() - startedAt,
      };
    }
  }

  /**
   * "Télécharger" on an item: pull the media file onto local disk, resuming a
   * partial download if one is there. Once it lands, playback never touches the
   * provider again.
   */
  async download(itemId: number, options: { signal?: AbortSignal } = {}): Promise<DownloadReport> {
    const library = this.#options.library;
    const item = library.item(itemId);
    if (!item) throw new UpstreamError(`unknown VOD item ${itemId}`, 404);
    if (this.#running.has(itemId)) {
      return this.#report(itemId, false, 0, 0, this.#now(), "already downloading");
    }
    if (item.state === "ready" && item.filePath) {
      return { itemId, ok: true, bytes: item.bytesDone, resumedFrom: item.bytesDone, path: item.filePath, durationMs: 0 };
    }

    const startedAt = this.#now();
    const controller = new AbortController();
    this.#running.set(itemId, controller);
    if (options.signal) {
      options.signal.addEventListener("abort", () => controller.abort(), { once: true });
    }

    const source = item.sourceId === null ? null : library.source(item.sourceId);
    const accountId = source?.accountId;
    let lease: SlotLease | null = null;

    const target = this.#targetPath(item);
    const partial = `${target}.part`;

    try {
      if (!accountId) throw new UpstreamError("this item has no master account any more");
      if (this.#options.acquireLease) {
        lease = await this.#options.acquireLease(accountId);
        if (!lease) throw new UpstreamError(`master account ${accountId} is busy streaming`, 503);
      }

      this.#emit({ type: "vod-download-start", item: itemId, title: item.title });
      library.setState(itemId, "downloading", { error: null, filePath: null });

      await mkdir(path.dirname(target), { recursive: true });
      const resumeFrom = await fileSize(partial);
      const written = await this.#fetchTo(item, accountId, partial, resumeFrom, controller.signal);

      if (controller.signal.aborted) {
        // The partial file stays: cancelling is not the same as discarding, and
        // the next attempt resumes from where this one stopped.
        library.setState(itemId, "pending", { bytesDone: written, error: null });
        this.#emit({ type: "vod-download-cancelled", item: itemId, title: item.title });
        return { ...this.#report(itemId, false, written, resumeFrom, startedAt), cancelled: true };
      }

      await rename(partial, target);
      library.setState(itemId, "ready", {
        filePath: target,
        bytesTotal: written,
        bytesDone: written,
        error: null,
        downloadedAt: this.#now(),
      });
      this.#emit({ type: "vod-download-done", item: itemId, title: item.title, bytes: written });
      return { itemId, ok: true, bytes: written, resumedFrom: resumeFrom, path: target, durationMs: this.#now() - startedAt };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      library.setState(itemId, "failed", { error: message, bytesDone: await fileSize(partial) });
      this.#emit({ type: "vod-download-failed", item: itemId, title: item.title, message });
      return { ...this.#report(itemId, false, 0, 0, startedAt), error: message };
    } finally {
      lease?.release();
      this.#running.delete(itemId);
    }
  }

  /** Stops a download in progress. The partial file is kept for a resume. */
  cancel(itemId: number): boolean {
    const controller = this.#running.get(itemId);
    if (!controller) return false;
    controller.abort();
    return true;
  }

  /** Deletes the local copy, keeping the library entry. */
  async removeFile(itemId: number): Promise<boolean> {
    const item = this.#options.library.item(itemId);
    if (!item) return false;
    this.cancel(itemId);
    const target = item.filePath ?? this.#targetPath(item);
    await rm(target, { force: true });
    await rm(`${target}.part`, { force: true });
    this.#options.library.setState(itemId, "pending", {
      filePath: null,
      bytesDone: 0,
      bytesTotal: 0,
      error: null,
      downloadedAt: null,
    });
    return true;
  }

  /** Deletes the entry AND its bytes — what the "delete" button in the panel does. */
  async removeItem(itemId: number): Promise<boolean> {
    const item = this.#options.library.item(itemId);
    if (!item) return false;
    this.cancel(itemId);
    const target = item.filePath ?? this.#targetPath(item);
    await rm(target, { force: true });
    await rm(`${target}.part`, { force: true });
    this.#options.library.removeItem(itemId);
    return true;
  }

  // ----------------------------------------------------------- internals

  #targetPath(item: VodItem): string {
    const extension = item.container && SAFE_EXT.test(item.container) ? item.container : "bin";
    // Named by id, not by title: titles are editable, and a rename must not
    // orphan the bytes on disk.
    return path.join(this.#options.dir, `${item.id}.${extension}`);
  }

  async #fetchTo(
    item: VodItem,
    accountId: string,
    partial: string,
    resumeFrom: number,
    signal: AbortSignal
  ): Promise<number> {
    const identity = this.#options.identityFor(accountId);
    const headers: Record<string, string> = { ...masterSignature(identity) };
    if (resumeFrom > 0) headers.range = `bytes=${resumeFrom}-`;
    // Same rule as everywhere else: the request is the account's signature. The
    // only extra field is a resume offset, which says nothing about a viewer.
    assertMirrorsMasterSignature(headers, identity, { allow: ["range"] });

    const response = await this.#options.transport.open({ url: item.sourceUrl, headers, signal });
    try {
      if (response.status === 416) return resumeFrom; // already complete
      if (response.status < 200 || response.status >= 300) {
        throw new UpstreamError(`origin refused the download (HTTP ${response.status})`, response.status);
      }
      // A 200 to a resume request means the origin ignored Range: start over
      // rather than append a second copy of the file to the first.
      const append = resumeFrom > 0 && response.status === 206;
      if (resumeFrom > 0 && !append) await rm(partial, { force: true });

      const declared = Number(response.headers["content-length"] ?? 0);
      const total = append ? resumeFrom + declared : declared;
      const cap = this.#options.maxFileBytes ?? 0;
      if (cap > 0 && total > cap) {
        throw new UpstreamError(`file is ${total} bytes, over the ${cap} byte limit`);
      }
      this.#options.library.setState(item.id, "downloading", {
        bytesTotal: total,
        bytesDone: append ? resumeFrom : 0,
      });

      const sink = createWriteStream(partial, { flags: append ? "a" : "w" });
      let written = append ? resumeFrom : 0;
      let sinceUpdate = 0;
      const every = this.#options.progressEveryBytes ?? 2 * 1024 * 1024;

      try {
        for await (const piece of response.body) {
          if (signal.aborted) break;
          if (cap > 0 && written + piece.byteLength > cap) {
            throw new UpstreamError(`download exceeded the ${cap} byte limit`);
          }
          if (!sink.write(piece)) await drainStream(sink);
          written += piece.byteLength;
          sinceUpdate += piece.byteLength;
          // Progress is persisted in coarse steps: the panel wants a moving bar,
          // not a database write per network packet.
          if (sinceUpdate >= every) {
            sinceUpdate = 0;
            this.#options.library.setState(item.id, "downloading", { bytesDone: written });
          }
        }
      } finally {
        await new Promise<void>((resolve) => sink.end(resolve));
      }
      return written;
    } finally {
      response.close();
    }
  }

  #report(
    itemId: number,
    ok: boolean,
    bytes: number,
    resumedFrom: number,
    startedAt: number,
    error?: string
  ): DownloadReport {
    return { itemId, ok, bytes, resumedFrom, error, durationMs: this.#now() - startedAt };
  }

  #now(): number {
    return this.#options.now ? this.#options.now() : Date.now();
  }

  #emit(event: DownloadEvent): void {
    this.#options.onEvent?.(event);
  }
}

async function fileSize(file: string): Promise<number> {
  try {
    return (await stat(file)).size;
  } catch {
    return 0;
  }
}

function drainStream(sink: NodeJS.WritableStream): Promise<void> {
  return new Promise((resolve) => sink.once("drain", () => resolve()));
}
