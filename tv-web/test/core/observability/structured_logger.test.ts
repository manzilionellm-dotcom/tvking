// =========================================================
//  structured_logger.test.ts
// =========================================================
//  Couvre le format JSON-Lines + fan-out + resilience aux sinks
//  defaillants. Miroir des tests du logger Dart phone.
// =========================================================

import { describe, it, expect, beforeEach } from 'vitest';
import { logger } from '../../../src/core/observability/structured_logger.js';

describe('StructuredLogger', () => {
  beforeEach(() => {
    logger.clearSinks();
  });

  it('emet un JSON-Lines avec les champs canoniques', () => {
    const captured: string[] = [];
    logger.addSink((line) => captured.push(line));

    logger.info('xtream', 'auth.success', { host: 'example.com' });

    expect(captured).toHaveLength(1);
    const parsed = JSON.parse(captured[0] ?? '{}') as Record<string, unknown>;
    expect(parsed['lvl']).toBe('info');
    expect(parsed['domain']).toBe('xtream');
    expect(parsed['event']).toBe('auth.success');
    expect(typeof parsed['ts']).toBe('string');
    expect((parsed['ts'] as string).endsWith('Z')).toBe(true);
    expect((parsed['ctx'] as Record<string, unknown>)['host']).toBe('example.com');
  });

  it("omet `ctx` quand il est vide pour compacite", () => {
    const captured: string[] = [];
    logger.addSink((line) => captured.push(line));

    logger.error('storage', 'write_failed');

    const parsed = JSON.parse(captured[0] ?? '{}') as Record<string, unknown>;
    expect('ctx' in parsed).toBe(false);
    expect(parsed['lvl']).toBe('error');
  });

  it('couvre les 3 niveaux avec le short name correct', () => {
    const captured: string[] = [];
    logger.addSink((line) => captured.push(line));

    logger.info('d', 'e');
    logger.warn('d', 'e');
    logger.error('d', 'e');

    expect(captured).toHaveLength(3);
    expect(
      captured.map(
        (s) => (JSON.parse(s) as Record<string, unknown>)['lvl'] as string,
      ),
    ).toEqual(['info', 'warn', 'error']);
  });

  it('diffuse a tous les sinks dans l\'ordre d\'ajout', () => {
    const a: string[] = [];
    const b: string[] = [];
    logger.addSink((s) => a.push(s));
    logger.addSink((s) => b.push(s));

    logger.info('d', 'e');

    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    expect(a[0]).toBe(b[0]);
  });

  it("un sink qui throw n'empeche pas les autres de recevoir l'evenement", () => {
    const before: string[] = [];
    const after: string[] = [];
    logger.addSink((s) => before.push(s));
    logger.addSink(() => {
      throw new Error('sink defaillant');
    });
    logger.addSink((s) => after.push(s));

    logger.warn('d', 'e');

    expect(before).toHaveLength(1);
    expect(after).toHaveLength(1);
  });
});
