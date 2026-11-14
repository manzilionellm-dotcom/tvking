// Pont propre à NOVATUBE 4K. Le panel conserve ses routes et ses contrôles.
// Une MAC inscrite dans ce circuit reçoit uniquement sa licence NOVATUBE ;
// le mécanisme de fourniture de chaînes Gold ne fait pas partie de ce circuit.
import {
  handleNovatube4k, isNovatube4kMac, NOVATUBE4K_APP_ID,
} from './novatube4k.js';
import { notifyNovatubePanelMutation } from './novatube4k-panel.js';
import { handleNovatubePanelAdmin } from './novatube4k-panel-admin.js';
import { handleNovatube4kTransfer } from './novatube4k-transfer.js';
import { handleNovatube4kTrialExtend } from './novatube4k-trial.js';
import { handleNovatubeRecoveryAdmin } from './novatube4k-recovery.js';
import { handlePanelAlertsApi } from './panel-alerts-api.js';

function unavailable() {
  return Response.json({ error: 'novatube4k_unavailable' }, {
    status: 503, headers: { 'Cache-Control': 'no-store' },
  });
}
const TOO_LARGE = Symbol('body_too_large');
function oversized() {
  return Response.json({ error: 'body_too_large' }, {
    status: 413, headers: { 'Cache-Control': 'no-store' },
  });
}

// Les anciens clients utilisent des routes historiques basées sur la MAC.
// Les nouvelles fiches NOVATUBE doivent toujours fournir leur clé propre,
// y compris si quelqu'un essaie ces anciennes routes avec leur MAC Atlas.
async function legacyDeviceMac(request, url, ctx) {
  // Même découpage que le routeur historique (slashes vides ignorés).
  const parts = url.pathname.split('/').filter(Boolean);
  const path = '/' + parts.join('/');
  const direct = path.match(/^\/(?:api\/(?:device-source|self-source|status|history|backup)|config)\/([^/]+)$/);
  const box = parts[0] === 'api' && parts[1] === 'box' && ['ws', 'wait', 'ack'].includes(parts[2]);
  let candidate = direct?.[1] || (box
    ? (parts[2] === 'ws' ? url.searchParams.get('mac') : parts[3] || url.searchParams.get('mac'))
    : '');
  if (['/api/heartbeat', '/api/blackbox', '/api/feedback', '/api/gold-trial', '/api/v1/device/trial'].includes(path)) {
    // La boîte noire historique conserve 32 Kio ; 1 Mio laisse aussi une
    // marge pour l'échappement JSON et les inventaires des anciens clients.
    const body = await activationBody(request, ctx, 1024 * 1024);
    if (body === TOO_LARGE) return TOO_LARGE;
    candidate = body?.mac || url.searchParams.get('mac') || '';
  }
  try { candidate = decodeURIComponent(candidate || '').trim().toUpperCase(); }
  catch { return ''; }
  if (path === '/api/gold-trial' || path === '/api/v1/device/trial') {
    // Même normalisation que le wrapper Gold historique pour ses alias MK.
    candidate = candidate.replace(/[-.]/g, ':');
    if (candidate.startsWith('MK')) {
      const hex = candidate.slice(2).replace(/[^0-9A-F]/g, '');
      if (hex.length === 10) candidate = 'MK:' + hex.match(/../g).join(':');
    }
  }
  return /^MK(?::[0-9A-F]{2}){5}$/.test(candidate) ? candidate : '';
}

// Le corps d'une activation est petit. Une lecture bornée évite qu'une requête
// malformée monopolise la mémoire avant les contrôles de l'API existante.
async function activationBody(request, ctx, limit = 16384) {
  const copy = request.clone();
  const reader = copy.body?.getReader();
  if (!reader) return null;
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        // Le refus 413 est définitif : annuler les DEUX branches du tee,
        // sinon l'annulation du clone attendrait un original jamais consommé.
        ctx.waitUntil(Promise.allSettled([reader.cancel(), request.body.cancel()]));
        return TOO_LARGE;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch { return null; }
}

export function createNovatube4kEntry(legacy, original, hooks = {}) {
  return {
    ...legacy,
    async fetch(request, env, ctx) {
      const url = new URL(request.url);
      const ownerAlerts = await handlePanelAlertsApi(request, env, ctx, original, hooks);
      if (ownerAlerts) return ownerAlerts;
      try {
        const recovery = await handleNovatubeRecoveryAdmin(request, env, ctx, original, hooks);
        if (recovery) return recovery;
      } catch {
        return Response.json({ ok: false, error: 'recovery_unavailable',
          message: 'La réassociation est momentanément indisponible.' },
        { status: 503, headers: { 'Cache-Control': 'no-store, private' } });
      }
      const panelAdmin = await handleNovatubePanelAdmin(request, env, ctx, original);
      if (panelAdmin) return panelAdmin;
      if (url.pathname.startsWith('/api/novatube4k/')) {
        try {
          const relay = (method, path, body) => {
            // Le module appelle seulement des chemins constants contrôlés.
            // Ni clé d'installation, ni JWT panel ne sortent dans un sous-appel.
            const headers = new Headers({ 'Content-Type': 'application/json' });
            for (const name of ['CF-Connecting-IP', 'CF-IPCountry']) {
              const value = request.headers.get(name);
              if (value) headers.set(name, value);
            }
            const forwarded = new Request(new URL(path, url), {
              method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
              ...(request.cf ? { cf: request.cf } : {}),
            });
            return original.fetch(forwarded, env, ctx);
          };
          return await handleNovatube4k(request, env, {
            readSources: (mac) => {
              // Le routeur existant attend les « : » littéraux. La valeur est
              // déjà validée par le module (MK + cinq octets hexadécimaux).
              const sourceUrl = new URL('/api/device-source/' + mac, url);
              return original.fetch(new Request(sourceUrl, {
                method: 'GET', headers: request.headers,
              }), env, ctx);
            },
            relay,
            ...hooks,
          });
        } catch {
          // Ni clé appareil ni identifiants de liste ne sont écrits dans les logs.
          console.error(JSON.stringify({ event: 'novatube4k_request_failed' }));
          return unavailable();
        }
      }
      const legacyMac = await legacyDeviceMac(request, url, ctx);
      if (legacyMac === TOO_LARGE) return oversized();
      if (legacyMac) {
        try {
          if (await isNovatube4kMac(env, legacyMac)) {
            return Response.json({ error: 'novatube4k_device_key_required' }, {
              status: 401, headers: { 'Cache-Control': 'no-store, private' },
            });
          }
        } catch { return unavailable(); }
      }
      if (url.pathname.split('/').filter(Boolean).join('/') === 'api/v1/transfer' && request.method === 'POST') {
        const body = await activationBody(request, ctx);
        if (body === TOO_LARGE) return oversized();
        try {
          const transfer = await handleNovatube4kTransfer(request, env, ctx, original, hooks, body);
          if (transfer) return transfer;
        } catch {
          console.error(JSON.stringify({ event: 'novatube4k_transfer_failed' }));
          return unavailable();
        }
      }
      if (url.pathname.split('/').filter(Boolean).join('/') === 'api/v1/trial-extend' && request.method === 'POST') {
        const body = await activationBody(request, ctx);
        if (body === TOO_LARGE) return oversized();
        try {
          const trial = await handleNovatube4kTrialExtend(request, env, ctx, original, hooks, body);
          if (trial) return trial;
        } catch {
          console.error(JSON.stringify({ event: 'novatube4k_trial_extension_failed' }));
          return unavailable();
        }
      }
      if (url.pathname.split('/').filter(Boolean).join('/') === 'api/v1/activate' && request.method === 'POST') {
        const body = await activationBody(request, ctx);
        if (body === TOO_LARGE) return oversized();
        const mac = typeof body?.mac === 'string' ? body.mac.trim().toUpperCase() : '';
        if (/^MK(?::[0-9A-F]{2}){5}$/.test(mac)) {
          let linked;
          try { linked = await isNovatube4kMac(env, mac); }
          catch { return unavailable(); }
          if (linked) {
            const headers = new Headers(request.headers);
            headers.delete('content-length');
            headers.set('content-type', 'application/json');
            const forwarded = new Request(request, {
              headers,
              body: JSON.stringify({ ...body, mac, app_id: NOVATUBE4K_APP_ID }),
            });
            // L'API d'origine vérifie le JWT, l'origine, le rôle, l'appartenance
            // revendeur, les crédits et l'idempotence. Aucune permission ajoutée.
            return original.fetch(forwarded, env, ctx);
          }
        }
      }
      const response = await legacy.fetch(request, env, ctx);
      // La mutation a déjà passé l'authentification et tous les contrôles du
      // Worker courant. Le réveil NOVATUBE n'altère jamais sa réponse.
      const notification = notifyNovatubePanelMutation(request, response, env).catch(() => {
        console.error(JSON.stringify({ event: 'novatube4k_panel_wakeup_failed' }));
      });
      if (ctx && typeof ctx.waitUntil === 'function') ctx.waitUntil(notification);
      else await notification;
      return response;
    },
  };
}
