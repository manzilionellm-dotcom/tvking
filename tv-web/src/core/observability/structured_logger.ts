// =========================================================
//  structured_logger.ts — Logger JSON-Lines pour tv-web
// =========================================================
//  Miroir TypeScript de `lib/core/observability/structured_logger.dart`
//  du projet Flutter phone. Meme conventions, meme format JSON-Lines,
//  pour qu'on puisse aggreger les logs des 2 plateformes dans un
//  meme collector si on en deploie un.
//
//  Forme d'un evenement (1 ligne JSON) :
//    {
//      "ts": "2026-06-01T13:00:00.000Z",
//      "lvl": "info",
//      "domain": "tv",          // 'tv' | 'cast' | 'player' | 'storage'
//      "event": "playlist.loaded",
//      "ctx": { "channelCount": 412 }
//    }
//
//  Sinks par defaut : console.log si !import.meta.env.PROD. En prod
//  on garde le canal silencieux par defaut — un sink supplementaire
//  peut etre branche par le caller pour exporter ailleurs (fichier,
//  endpoint distant) sans toucher au logger.
// =========================================================

export type LogLevel = 'info' | 'warn' | 'error';

export type LogSink = (jsonLine: string) => void;

interface LogEvent {
  readonly ts: string;
  readonly lvl: LogLevel;
  readonly domain: string;
  readonly event: string;
  readonly ctx?: Record<string, unknown>;
}

class StructuredLogger {
  private readonly sinks: LogSink[] = [];

  /**
   * Setup par defaut : en mode developpement, log dans la console
   * (visible Chrome DevTools / VS Code terminal). En prod, silencieux
   * tant qu'on n'a pas branche de sink explicite.
   *
   * On detecte l'env via `import.meta.env.DEV` (Vite) — fallback sur
   * `true` si on tourne hors-Vite (tests Vitest, etc.) pour avoir
   * du feedback en debug.
   */
  constructor() {
    const isDev =
      typeof import.meta !== 'undefined' &&
      import.meta.env !== undefined &&
      Boolean(import.meta.env.DEV);
    if (isDev) {
      this.sinks.push((line) => {
        // eslint-disable-next-line no-console
        console.log(line);
      });
    }
  }

  addSink(sink: LogSink): void {
    this.sinks.push(sink);
  }

  /** Vide la liste des sinks. A reserver aux tests. */
  clearSinks(): void {
    this.sinks.length = 0;
  }

  info(domain: string, event: string, ctx?: Record<string, unknown>): void {
    this.emit('info', domain, event, ctx);
  }

  warn(domain: string, event: string, ctx?: Record<string, unknown>): void {
    this.emit('warn', domain, event, ctx);
  }

  error(domain: string, event: string, ctx?: Record<string, unknown>): void {
    this.emit('error', domain, event, ctx);
  }

  private emit(
    lvl: LogLevel,
    domain: string,
    event: string,
    ctx?: Record<string, unknown>,
  ): void {
    const payload: LogEvent = {
      ts: new Date().toISOString(),
      lvl,
      domain,
      event,
      ...(ctx && Object.keys(ctx).length > 0 ? { ctx } : {}),
    };
    let line: string;
    try {
      line = JSON.stringify(payload);
    } catch {
      // Cycle dans ctx, valeur non-JSON, etc. — fallback texte pour
      // ne PAS perdre l'evenement.
      line = `${payload.ts} ${lvl} ${domain}.${event} (ctx non-serialisable: ${Object.keys(
        ctx ?? {},
      ).join(',')})`;
    }
    for (const sink of this.sinks) {
      try {
        sink(line);
      } catch {
        // Un sink defaillant ne doit pas bloquer les autres.
      }
    }
  }
}

export const logger = new StructuredLogger();

// Export du type pour les tests et pour qu'un caller puisse declarer
// un sink type-safe.
export type { StructuredLogger };
