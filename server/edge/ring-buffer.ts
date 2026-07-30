/*
 * Fixed-capacity circular buffer of stream chunks — the edge cache itself.
 *
 * Zero-copy: chunks are stored by reference and handed to subscribers by
 * reference. Nothing here ever copies, slices or concatenates payload bytes,
 * so fanning one upstream stream out to 200 clients costs one buffer, not 200.
 * The bytes are therefore SHARED and MUST be treated as read-only by every
 * consumer (writing into a delivered chunk would corrupt every other client).
 *
 * Eviction is FIFO under two caps — total bytes and total chunks — so memory
 * is bounded no matter the upstream bitrate.
 */

export interface StreamChunk {
  /** Monotonic, gap-free sequence number assigned on push. */
  readonly seq: number;
  /** Shared, read-only payload view. */
  readonly data: Uint8Array;
  /** Clock time (ms) at which the chunk arrived from the origin. */
  readonly at: number;
}

export interface RingBufferOptions {
  /** Hard cap on retained payload bytes. */
  maxBytes: number;
  /** Hard cap on retained chunks (bounds slot-array memory). */
  maxChunks: number;
}

export class RingBuffer {
  #slots: Array<StreamChunk | undefined>;
  #head = 0; // next write position
  #count = 0;
  #bytes = 0;
  #nextSeq = 0;
  #evicted = 0;
  #maxBytes: number;

  constructor(options: RingBufferOptions) {
    const { maxBytes, maxChunks } = options;
    if (!Number.isInteger(maxChunks) || maxChunks < 1) {
      throw new RangeError(`maxChunks must be a positive integer, got ${maxChunks}`);
    }
    if (!(maxBytes > 0)) {
      throw new RangeError(`maxBytes must be > 0, got ${maxBytes}`);
    }
    this.#slots = new Array<StreamChunk | undefined>(maxChunks);
    this.#maxBytes = maxBytes;
  }

  /** Retained chunks. */
  get size(): number {
    return this.#count;
  }

  /** Retained payload bytes. */
  get bytes(): number {
    return this.#bytes;
  }

  get capacityChunks(): number {
    return this.#slots.length;
  }

  get capacityBytes(): number {
    return this.#maxBytes;
  }

  /** Sequence number the next pushed chunk will get. */
  get nextSeq(): number {
    return this.#nextSeq;
  }

  /** Sequence number of the oldest retained chunk (= nextSeq when empty). */
  get oldestSeq(): number {
    return this.#nextSeq - this.#count;
  }

  /** Chunks dropped by eviction since construction. */
  get evictedChunks(): number {
    return this.#evicted;
  }

  /** Appends a chunk (by reference) and evicts from the tail until in cap. */
  push(data: Uint8Array, at: number): StreamChunk {
    if (data.byteLength > this.#maxBytes) {
      // A single chunk larger than the whole cache would evict everything and
      // still not fit; refuse rather than silently emptying the buffer.
      throw new RangeError(
        `chunk of ${data.byteLength}B exceeds ring capacity of ${this.#maxBytes}B`
      );
    }

    const chunk: StreamChunk = { seq: this.#nextSeq, data, at };
    this.#nextSeq += 1;

    if (this.#count === this.#slots.length) this.#evictOldest();
    this.#slots[this.#head] = chunk;
    this.#head = (this.#head + 1) % this.#slots.length;
    this.#count += 1;
    this.#bytes += data.byteLength;

    while (this.#bytes > this.#maxBytes && this.#count > 1) this.#evictOldest();
    return chunk;
  }

  /**
   * Chunks with `seq >= from`, oldest first. A caller that fell behind past
   * eviction gets what survives — compare `result[0].seq` with `from` to
   * detect (and count) the gap.
   */
  since(from: number): StreamChunk[] {
    const out: StreamChunk[] = [];
    const start = Math.max(from, this.oldestSeq);
    for (let seq = start; seq < this.#nextSeq; seq += 1) {
      const chunk = this.#at(seq);
      if (chunk) out.push(chunk);
    }
    return out;
  }

  /**
   * The newest chunks totalling at most `maxBytes`, oldest first. This is the
   * burst handed to a joining client so playback can start immediately instead
   * of waiting for the next upstream chunk.
   */
  tail(maxBytes: number): StreamChunk[] {
    if (maxBytes <= 0 || this.#count === 0) return [];
    const out: StreamChunk[] = [];
    let total = 0;
    for (let seq = this.#nextSeq - 1; seq >= this.oldestSeq; seq -= 1) {
      const chunk = this.#at(seq);
      if (!chunk) break;
      if (total + chunk.data.byteLength > maxBytes && out.length > 0) break;
      total += chunk.data.byteLength;
      out.push(chunk);
    }
    out.reverse();
    return out;
  }

  clear(): void {
    this.#slots.fill(undefined);
    this.#head = 0;
    this.#count = 0;
    this.#bytes = 0;
  }

  #at(seq: number): StreamChunk | undefined {
    if (seq < this.oldestSeq || seq >= this.#nextSeq) return undefined;
    const offset = this.#nextSeq - 1 - seq; // 0 = newest
    const index = (this.#head - 1 - offset + this.#slots.length * 2) % this.#slots.length;
    return this.#slots[index];
  }

  #evictOldest(): void {
    if (this.#count === 0) return;
    const index = (this.#head - this.#count + this.#slots.length) % this.#slots.length;
    const chunk = this.#slots[index];
    if (chunk) this.#bytes -= chunk.data.byteLength;
    this.#slots[index] = undefined;
    this.#count -= 1;
    this.#evicted += 1;
  }
}
