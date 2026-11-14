// État local minimal, partagé avec le service worker. Aucune identité, aucun
// JWT, endpoint ou contenu de notification n'est conservé dans cette base.
const DB = 'panel-alert-events-v1';
type Consent = { id: 'consent'; nonce: string; enabled: boolean; expires_at: number };
function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB, 2);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains('seen')) request.result.createObjectStore('seen', { keyPath: 'id' });
      if (!request.result.objectStoreNames.contains('control')) request.result.createObjectStore('control', { keyPath: 'id' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error('consent_storage_unavailable'));
  });
}
function randomNonce() { return crypto.randomUUID(); }
async function write(value: Consent, expected?: string): Promise<boolean> {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('control', 'readwrite');
      const store = tx.objectStore('control');
      let changed = false;
      const read = store.get('consent');
      read.onsuccess = () => {
        if (expected !== undefined && read.result?.nonce !== expected) return;
        store.put(value); changed = true;
      };
      tx.oncomplete = () => resolve(changed);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally { db.close(); }
}
function notify(worker: ServiceWorker | null | undefined, type: string, nonce: string): Promise<boolean> {
  if (!worker) return Promise.resolve(false);
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    const timer = window.setTimeout(() => { channel.port1.close(); resolve(false); }, 1000);
    channel.port1.onmessage = (event) => { window.clearTimeout(timer); channel.port1.close(); resolve(event.data?.ok === true); };
    worker.postMessage({ type, nonce }, [channel.port2]);
  });
}
export async function disablePanelConsent(registration?: ServiceWorkerRegistration | null): Promise<void> {
  const nonce = randomNonce();
  // Le message coupe la mémoire du worker immédiatement et persiste aussi
  // la coupure s'il doit terminer après la fermeture de l'onglet.
  const stopped = notify(registration?.active || navigator.serviceWorker?.controller, 'panel-consent-off', nonce);
  await Promise.all([write({ id: 'consent', nonce, enabled: false, expires_at: 0 }), stopped]);
  const existing = await registration?.getNotifications();
  existing?.forEach((item) => item.close());
}
export async function beginPanelConsent(): Promise<string> {
  const nonce = randomNonce();
  await write({ id: 'consent', nonce, enabled: false, expires_at: 0 });
  return nonce;
}
export async function confirmPanelConsent(nonce: string, expiresAt: number, registration: ServiceWorkerRegistration): Promise<boolean> {
  if (!Number.isSafeInteger(expiresAt) || expiresAt <= Date.now()) return false;
  const confirmed = await write({ id: 'consent', nonce, enabled: true, expires_at: expiresAt }, nonce);
  if (!confirmed) return false;
  const acknowledged = await notify(registration.active || navigator.serviceWorker?.controller, 'panel-consent-on', nonce);
  if (!acknowledged) {
    await write({ id: 'consent', nonce, enabled: false, expires_at: 0 }, nonce);
    return false;
  }
  const current = await read();
  return current?.nonce === nonce && current.enabled === true && current.expires_at > Date.now();
}
async function read(): Promise<Consent | undefined> {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction('control').objectStore('control').get('consent');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  } finally { db.close(); }
}
export async function hasPanelConsent(): Promise<boolean> {
  const current = await read();
  return current?.enabled === true && current.expires_at > Date.now();
}
