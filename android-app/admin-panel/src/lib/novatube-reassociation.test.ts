// @vitest-environment jsdom
// Vérifie les vrais chemins et corps du client HTTP, sans appel de production.
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { novatubeReassociationApi, setToken } from './api';

const MAC = 'MK:AA:BB:CC:DD:EE';
const CODE = 'ABCD-1234-EFGH';
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);
  setToken('fixture-token');
});
afterEach(() => { setToken(null); vi.unstubAllGlobals(); });

it('vérifie la capacité par GET sans mettre le code d’assistance dans l’URL', async () => {
  const abort = new AbortController();
  await novatubeReassociationApi.capability(MAC, abort.signal);
  const [url, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe(`/api/v1/novatube4k/reassociate?mac=${encodeURIComponent(MAC)}`);
  expect(options.method).toBe('GET');
  expect(options.signal).toBe(abort.signal);
  expect(options.body).toBeUndefined();
  expect(options.headers).toMatchObject({ Authorization: 'Bearer fixture-token' });
});

it('envoie le code uniquement dans le corps de l’aperçu authentifié', async () => {
  await novatubeReassociationApi.preview(MAC, CODE);
  const [url, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe('/api/v1/novatube4k/reassociate/preview');
  expect(options.method).toBe('POST');
  expect(JSON.parse(options.body as string)).toEqual({ mac: MAC, code: CODE });
  expect(options.cache).toBe('no-store');
  expect(options.headers).toMatchObject({ Authorization: 'Bearer fixture-token' });
});

it('approuve la demande exacte sans appeler activation, suppression ou remise à zéro', async () => {
  await novatubeReassociationApi.approve(MAC, CODE, 'request-fixture');
  expect(fetchMock).toHaveBeenCalledTimes(1);
  const [url, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe('/api/v1/novatube4k/reassociate/approve');
  expect(options.method).toBe('POST');
  expect(JSON.parse(options.body as string)).toEqual({ mac: MAC, code: CODE, request_id: 'request-fixture' });
  expect(options.headers).toMatchObject({ Authorization: 'Bearer fixture-token' });
});
