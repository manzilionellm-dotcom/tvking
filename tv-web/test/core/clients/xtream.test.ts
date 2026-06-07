// =========================================================
//  xtream.test.ts — Client Xtream Codes
// =========================================================
//  Tests purs (sans reseau reel) — on stub `fetch` global via vi.
//  Couvre :
//    - normalisation des URLs serveur (trailing slash, /player_api.php
//      colle par erreur)
//    - construction d'URLs API et de stream
//    - parsing des reponses authenticate / get_live_categories /
//      get_live_streams
//    - mapping vers Channel (id, name, url, group, epgId)
//    - erreurs typees XtreamError (auth_failed, network, invalid_response)
// =========================================================

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  XtreamClient,
  XtreamError,
  normalizeServerUrl,
} from '../../../src/core/clients/xtream.js';
import { logger } from '../../../src/core/observability/structured_logger.js';

beforeEach(() => {
  logger.clearSinks();
  vi.restoreAllMocks();
});

function mockFetch(
  responses: Array<{ status?: number; body: unknown; ok?: boolean }>,
): void {
  let i = 0;
  globalThis.fetch = vi.fn(async () => {
    const r = responses[Math.min(i++, responses.length - 1)];
    if (!r) {
      throw new Error('no mocked response');
    }
    const json = r.body;
    return {
      ok: r.ok ?? (r.status === undefined || r.status < 400),
      status: r.status ?? 200,
      statusText: r.status === 401 ? 'Unauthorized' : 'OK',
      json: async () => {
        if (json instanceof Error) throw json;
        return json;
      },
      headers: new Headers(),
    } as unknown as Response;
  }) as typeof fetch;
}

describe('normalizeServerUrl', () => {
  it('retire le slash final', () => {
    expect(normalizeServerUrl('http://x.com/')).toBe('http://x.com');
    expect(normalizeServerUrl('http://x.com////')).toBe('http://x.com');
  });

  it("retire /player_api.php que l'utilisateur a colle par erreur", () => {
    expect(normalizeServerUrl('http://x.com/player_api.php')).toBe(
      'http://x.com',
    );
    expect(
      normalizeServerUrl(
        'http://x.com:8080/player_api.php?username=foo&password=bar',
      ),
    ).toBe('http://x.com:8080');
  });

  it('preserve le port', () => {
    expect(normalizeServerUrl('http://x.com:8080')).toBe('http://x.com:8080');
  });

  it('trim les espaces', () => {
    expect(normalizeServerUrl('  http://x.com  ')).toBe('http://x.com');
  });

  it("ne touche pas au scheme (http ou https)", () => {
    expect(normalizeServerUrl('https://x.com/')).toBe('https://x.com');
  });
});

describe('XtreamClient.buildApiUrl', () => {
  const client = new XtreamClient({
    serverUrl: 'http://srv.example.com',
    username: 'alice',
    password: 'wonder',
  });

  it("inclut user + pass en query string", () => {
    const url = client.buildApiUrl();
    expect(url).toContain('username=alice');
    expect(url).toContain('password=wonder');
    expect(url).toMatch(/\/player_api\.php\?/);
  });

  it("ajoute action quand fourni", () => {
    const url = client.buildApiUrl({ action: 'get_live_streams' });
    expect(url).toContain('action=get_live_streams');
  });

  it("url-encode les caracteres speciaux", () => {
    const sp = new XtreamClient({
      serverUrl: 'http://srv',
      username: 'mickaël&co',
      password: 'pass+word',
    });
    const url = sp.buildApiUrl();
    expect(url).toContain('username=micka%C3%ABl%26co');
    expect(url).toContain('password=pass%2Bword');
  });
});

describe('XtreamClient.buildLiveStreamUrl', () => {
  it("ts par defaut", () => {
    const c = new XtreamClient({
      serverUrl: 'http://srv',
      username: 'u',
      password: 'p',
    });
    expect(c.buildLiveStreamUrl(12345)).toBe('http://srv/live/u/p/12345.ts');
  });

  it('respecte container explicite (m3u8)', () => {
    const c = new XtreamClient({
      serverUrl: 'http://srv',
      username: 'u',
      password: 'p',
    });
    expect(c.buildLiveStreamUrl(12345, 'm3u8')).toBe(
      'http://srv/live/u/p/12345.m3u8',
    );
  });

  it('encode les credentials avec caracteres speciaux dans le path', () => {
    const c = new XtreamClient({
      serverUrl: 'http://srv',
      username: 'al/ice',
      password: 'wo nder',
    });
    expect(c.buildLiveStreamUrl(1)).toBe('http://srv/live/al%2Fice/wo%20nder/1.ts');
  });
});

describe('XtreamClient.authenticate', () => {
  const client = new XtreamClient({
    serverUrl: 'http://srv',
    username: 'u',
    password: 'p',
  });

  it('parse une reponse Active standard', async () => {
    mockFetch([
      {
        body: {
          user_info: {
            auth: 1,
            status: 'Active',
            exp_date: '1735689600',
            max_connections: '2',
            active_cons: '0',
            is_trial: '0',
          },
        },
      },
    ]);
    const info = await client.authenticate();
    expect(info.status).toBe('Active');
    expect(info.expiresAt).toBe(1735689600);
    expect(info.maxConnections).toBe(2);
    expect(info.isTrial).toBe(false);
  });

  it('detecte un compte trial', async () => {
    mockFetch([
      {
        body: {
          user_info: {
            auth: 1,
            status: 'Active',
            exp_date: '',
            is_trial: 1,
          },
        },
      },
    ]);
    const info = await client.authenticate();
    expect(info.isTrial).toBe(true);
    expect(info.expiresAt).toBeNull();
  });

  it('throw XtreamError(auth_failed) quand auth=0', async () => {
    mockFetch([
      {
        body: { user_info: { auth: 0, status: 'Disabled' } },
      },
    ]);
    await expect(client.authenticate()).rejects.toBeInstanceOf(XtreamError);
    await expect(client.authenticate()).rejects.toMatchObject({
      code: 'auth_failed',
    });
  });

  it('throw XtreamError(auth_failed) sur HTTP 401', async () => {
    mockFetch([{ status: 401, body: {} }]);
    await expect(client.authenticate()).rejects.toMatchObject({
      code: 'auth_failed',
    });
  });

  it('throw XtreamError(network) sur erreur reseau', async () => {
    globalThis.fetch = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    }) as typeof fetch;
    await expect(client.authenticate()).rejects.toMatchObject({
      code: 'network',
    });
  });

  it('throw XtreamError(invalid_response) sur reponse mal formee', async () => {
    mockFetch([{ body: { unrelated: 'shape' } }]);
    await expect(client.authenticate()).rejects.toMatchObject({
      code: 'invalid_response',
    });
  });

  it('throw XtreamError(invalid_response) si le body n\'est pas du JSON', async () => {
    globalThis.fetch = vi.fn(async () => {
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        json: async () => {
          throw new SyntaxError('not json');
        },
      } as unknown as Response;
    }) as typeof fetch;
    await expect(client.authenticate()).rejects.toMatchObject({
      code: 'invalid_response',
    });
  });
});

describe('XtreamClient.getLiveCategories', () => {
  const client = new XtreamClient({
    serverUrl: 'http://srv',
    username: 'u',
    password: 'p',
  });

  it('mappe correctement les categories', async () => {
    mockFetch([
      {
        body: [
          { category_id: '1', category_name: 'Sport', parent_id: 0 },
          { category_id: '2', category_name: 'News', parent_id: 0 },
          { category_id: '3', category_name: 'Sous Sport', parent_id: 1 },
        ],
      },
    ]);
    const cats = await client.getLiveCategories();
    expect(cats).toHaveLength(3);
    expect(cats[0]).toEqual({ id: '1', name: 'Sport', parentId: null });
    expect(cats[2]).toEqual({
      id: '3',
      name: 'Sous Sport',
      parentId: '1',
    });
  });

  it('renvoie [] si la reponse n\'est pas un tableau', async () => {
    mockFetch([{ body: { error: 'oops' } }]);
    expect(await client.getLiveCategories()).toEqual([]);
  });

  it("ignore les entrees sans category_id", async () => {
    mockFetch([
      {
        body: [
          { category_id: '1', category_name: 'OK' },
          { category_name: 'No id, skip' },
          { category_id: '', category_name: 'Empty id, skip' },
        ],
      },
    ]);
    const cats = await client.getLiveCategories();
    expect(cats).toHaveLength(1);
  });
});

describe('XtreamClient.getLiveStreams', () => {
  const client = new XtreamClient({
    serverUrl: 'http://srv',
    username: 'u',
    password: 'p',
  });

  it('mappe vers Channel avec URL correcte', async () => {
    mockFetch([
      {
        body: [
          {
            stream_id: 100,
            name: 'France 2',
            stream_icon: 'http://logo/f2.png',
            category_name: 'France',
            epg_channel_id: 'france2.fr',
            container_extension: 'ts',
          },
          {
            stream_id: 101,
            name: 'BFM TV',
            stream_icon: '',
            category_name: '',
            container_extension: 'm3u8',
          },
        ],
      },
    ]);
    const channels = await client.getLiveStreams();
    expect(channels).toHaveLength(2);
    expect(channels[0]).toMatchObject({
      id: 'xtream:100',
      name: 'France 2',
      url: 'http://srv/live/u/p/100.ts',
      logoUrl: 'http://logo/f2.png',
      group: 'France',
      epgId: 'france2.fr',
      orderIndex: 0,
    });
    expect(channels[1]).toMatchObject({
      id: 'xtream:101',
      name: 'BFM TV',
      url: 'http://srv/live/u/p/101.m3u8',
      logoUrl: null,
      group: null,
      epgId: null,
      orderIndex: 1,
    });
  });

  it("derive un nom par defaut si name est manquant", async () => {
    mockFetch([
      {
        body: [{ stream_id: 999 }],
      },
    ]);
    const [ch] = await client.getLiveStreams();
    expect(ch?.name).toBe('Chaîne 999');
  });

  it("ignore les entrees sans stream_id", async () => {
    mockFetch([
      {
        body: [
          { stream_id: 1, name: 'OK' },
          { name: 'Skip', stream_icon: 'x' },
        ],
      },
    ]);
    const channels = await client.getLiveStreams();
    expect(channels).toHaveLength(1);
  });

  it("ajoute category_id au query quand fourni", async () => {
    mockFetch([{ body: [] }]);
    await client.getLiveStreams('42');
    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const url = call?.[0] as string;
    expect(url).toContain('category_id=42');
  });
});
