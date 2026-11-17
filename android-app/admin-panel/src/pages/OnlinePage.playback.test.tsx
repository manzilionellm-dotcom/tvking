// @vitest-environment jsdom
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { JOURNAL_FRESH_MS, NOVATUBE_TV_VERSION } from '@/lib/blackbox';
import { OnlinePage } from './OnlinePage';

const api = vi.hoisted(() => ({ online: vi.fn(), devices: vi.fn(), journal: vi.fn() }));
vi.mock('@/lib/api', async (load) => ({
  ...await load<typeof import('@/lib/api')>(),
  onlineApi: { get: api.online }, devicesApi: { list: api.devices }, blackboxApi: { get: api.journal },
}));
vi.mock('@/components/AppLayout', () => ({
  AppLayout: ({ children }: { children: ReactNode }) => <main>{children}</main>,
}));

const mac = 'MK:11:22:33:44:55';
let root: Root;
let container: HTMLDivElement;
let channel = '';
beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  vi.useFakeTimers();
  vi.clearAllMocks();
  channel = '';
  container = document.createElement('div');
  root = createRoot(container);
  api.online.mockImplementation(async () => ({ onlineCount: 1, items: [{ mac, channel, lastSeen: Date.now() }] }));
  api.devices.mockResolvedValue({ items: [{ mac, platform: 'tv', app_version: NOVATUBE_TV_VERSION, device_model: 'SHIELD Android TV' }] });
  api.journal.mockImplementation(async () => ({
    mac, updated_at: Date.now(), text: '17/11 16:21:20 I [SON] [Chaîne démo] Seconde 10 : volume lecteur 1,0',
  }));
});
afterEach(async () => {
  await act(async () => root.unmount());
  vi.useRealTimers();
});
async function render() {
  await act(async () => root.render(<OnlinePage onLogout={() => {}} />));
}
async function advance(ms: number) {
  await act(async () => { await vi.advanceTimersByTimeAsync(ms); });
}

it('affiche le dernier signal de la TV avec son heure, puis donne la priorité au direct', async () => {
  await render();
  expect(container.textContent).toContain('NVIDIA Shield');
  expect(container.textContent).toContain('Chaîne démo');
  expect(container.textContent).toContain('Dernière chaîne signalée · 17/11 16:21:20 (heure TV)');
  await advance(4100);
  expect(api.journal).toHaveBeenCalledTimes(1);
  channel = 'En direct démo';
  await advance(2100);
  expect(container.textContent).toContain('▶ En direct démo');
  expect(container.textContent).not.toContain('Dernière chaîne signalée');
});

it('masque le journal ancien ou désactivé', async () => {
  api.journal.mockResolvedValue({
    mac, updated_at: Date.now() - JOURNAL_FRESH_MS - 1, text: '17/11 16:21:20 I [IMAGE] [Ancienne] Format vidéo',
  });
  await render();
  expect(container.textContent).toContain('NVIDIA Shield');
  expect(container.textContent).not.toContain('Ancienne');
});

it('ne consulte pas le journal des autres éditions', async () => {
  api.devices.mockResolvedValue({ items: [{ mac, app_version: '117', platform: 'tv' }] });
  await render();
  expect(api.journal).not.toHaveBeenCalled();
  expect(container.textContent).not.toContain('NovaTube TV');
});
