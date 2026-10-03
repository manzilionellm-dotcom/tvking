// API locale SANS secret, pour l'audit d'interface uniquement.
// Aucun mot de passe, aucun lien de flux réel : données factices.
// Ne pas déployer. Le panel (Vite) proxifie /api vers ce processus (:8787).

import http from 'node:http';

const NOW = Date.now();
const DAY = 86400000;

const admin = {
  id: 'usr_audit',
  email: 'admin',
  name: 'Audit local',
  role: 'super_admin',
  permissions: ['activate', 'sources', 'resellers', 'devices', 'activations'],
  credit_balance: 42,
  status: 'active',
};

const resellerUser = {
  id: 'rsl_demo',
  email: 'revendeur',
  name: 'Revendeur démo',
  role: 'reseller',
  permissions: ['activate', 'sources', 'resellers', 'devices', 'activations'],
  credit_balance: 12,
  status: 'active',
};

let sessionRole = 'admin';

const apps = [
  {
    id: 'app_demo',
    name: 'Zuno',
    package_name: 'com.example.zuno',
    primary_color: '#D63A30',
    tagline: 'Lecteur',
    default_iptv_server: null,
    default_playlist_type: 'xtream',
    pricing_json: null,
    download_url: null,
    is_active: 1,
    created_at: NOW - 10 * DAY,
    updated_at: NOW - DAY,
  },
];

const servers = [
  {
    id: 'srv_demo',
    label: 'Serveur démo',
    url: 'https://exemple.invalid',
    position: 1,
    enabled: 1,
    created_at: NOW - 5 * DAY,
    updated_at: NOW - DAY,
  },
];

const customers = [
  {
    id: 'cus_1',
    email: 'ada@exemple.invalid',
    name: 'Ada Martin',
    phone: '+33000000000',
    reseller_id: null,
    created_at: NOW - 20 * DAY,
  },
  {
    id: 'cus_2',
    email: null,
    name: 'Client sans e-mail',
    phone: null,
    reseller_id: null,
    created_at: NOW - 2 * DAY,
  },
];

const devices = [
  {
    id: 'dev_1',
    customer_id: 'cus_1',
    mac: 'MK:AA:BB:CC:DD:01',
    label: 'Salon',
    reseller_id: null,
    block_status: 'active',
    first_seen_at: NOW - 15 * DAY,
    last_seen_at: NOW - 60_000,
    customer_name: 'Ada Martin',
    customer_email: 'ada@exemple.invalid',
    device_model: 'Box démo',
    android_build: '1',
    android_release: '14',
    app_build: 100,
    platform: 'tv',
  },
  {
    id: 'dev_2',
    customer_id: 'cus_2',
    mac: 'MK:AA:BB:CC:DD:02',
    label: null,
    reseller_id: null,
    block_status: 'frozen',
    first_seen_at: NOW - 3 * DAY,
    last_seen_at: NOW - 2 * DAY,
    customer_name: 'Client sans e-mail',
    customer_email: null,
    device_model: null,
    android_build: null,
    android_release: null,
    app_build: null,
    platform: 'mobile',
  },
];

const licenses = [
  {
    id: 'lic_1',
    customer_id: 'cus_1',
    device_id: 'dev_1',
    app_id: 'app_demo',
    status: 'active',
    plan: 'yearly',
    started_at: NOW - 30 * DAY,
    expires_at: NOW + 300 * DAY,
    auto_renew: 0,
    customer_name: 'Ada Martin',
    customer_email: 'ada@exemple.invalid',
    device_mac: 'MK:AA:BB:CC:DD:01',
    device_label: 'Salon',
    app_name: 'Zuno',
  },
  {
    id: 'lic_2',
    customer_id: 'cus_2',
    device_id: 'dev_2',
    app_id: 'app_demo',
    status: 'expired',
    plan: 'monthly',
    started_at: NOW - 40 * DAY,
    expires_at: NOW - DAY,
    auto_renew: 0,
    customer_name: 'Client sans e-mail',
    customer_email: null,
    device_mac: 'MK:AA:BB:CC:DD:02',
    device_label: null,
    app_name: 'Zuno',
  },
];

const resellers = [
  {
    id: 'rsl_demo',
    email: 'revendeur@exemple.invalid',
    name: 'Revendeur démo',
    status: 'active',
    permissions: ['activate', 'devices'],
    credit_balance: 12,
    commission_rate: 0,
    created_at: NOW - 40 * DAY,
    devices: 3,
    licenses: 2,
    parent_reseller_id: null,
    sub_resellers: 0,
  },
  {
    id: 'rsl_wait',
    email: 'attente@exemple.invalid',
    name: 'Compte en attente',
    status: 'pending',
    permissions: [],
    credit_balance: 0,
    commission_rate: 0,
    created_at: NOW - DAY,
    devices: 0,
    licenses: 0,
    parent_reseller_id: null,
    sub_resellers: 0,
  },
  {
    id: 'rsl_stop',
    email: 'suspendu@exemple.invalid',
    name: 'Compte suspendu',
    status: 'suspended',
    permissions: [],
    credit_balance: 1,
    commission_rate: 0,
    created_at: NOW - 8 * DAY,
    devices: 0,
    licenses: 0,
    parent_reseller_id: null,
    sub_resellers: 0,
  },
];

let announcements = [
  {
    id: 1,
    title: 'Bienvenue',
    body: 'Message de démonstration pour l\'audit.',
    url: '',
    kind: 'info',
    cta: '',
    country: '',
    expires_at: NOW + 7 * DAY,
    active: 1,
    created_at: NOW - DAY,
  },
];
let announcementsEnabled = true;
let nextAnnId = 2;

let homeItems = [
  { key: 'recent', position: 0, enabled: 1, ribbon: '', featured: 0 },
  { key: 'favorites', position: 1, enabled: 1, ribbon: 'POPULAIRE', featured: 1 },
  { key: 'sport', position: 2, enabled: 1, ribbon: '', featured: 0 },
  { key: 'cinema', position: 3, enabled: 1, ribbon: '', featured: 0 },
];
let homeHistory = [{ id: 1, label: 'Version initiale', created_at: NOW - DAY }];

let forceMin = 0;
const forceLatest = Math.floor(NOW / 1000) - 3600;

let featured = { name: '', note: '' };
let theme = { appName: '', accent: '', bg: 'dark' };
let themeRules = [];
let ad = { enabled: false, url: '', skip: 5, freq: 'daily' };
let pricing = {
  currency: '€',
  lifetime: '15',
  yearly: '9,99',
  trialDays: 7,
  promoEnabled: false,
  promoMessage: '',
};
let planCosts = [
  { plan: 'monthly', credits: 1 },
  { plan: 'yearly', credits: 4 },
  { plan: 'lifetime', credits: 8 },
];
let feedbackPrompt = { enabled: false, message: '' };
const feedbackItems = [
  {
    id: 1,
    mac: 'MK:AA:BB:CC:DD:01',
    country: 'FR',
    rating: 5,
    message: 'Avis de démonstration.',
    created_at: NOW - 3 * DAY,
  },
];

const families = [
  {
    id: 'fam_1',
    name: 'Famille démo',
    source: { type: 'xtream', label: 'Ligne démo', server_url: 'https://exemple.invalid', username: 'demo' },
    member_count: 1,
    created_at: NOW - 4 * DAY,
  },
];
const familyMembers = {
  fam_1: [{ mac: 'MK:AA:BB:CC:DD:01', label: 'Salon', created_at: NOW - 4 * DAY }],
};
const familyLinks = {
  fam_1: [{ id: 'lnk_1', token: 'jeton-demo', label: 'Lien démo', created_at: NOW - DAY }],
};

function send(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(data),
  });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve({});
      try { resolve(JSON.parse(raw)); } catch { resolve({}); }
    });
  });
}

function authed(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') && h.slice(7).length > 0;
}

function currentUser() {
  return sessionRole === 'reseller' ? resellerUser : admin;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://127.0.0.1');
  const path = url.pathname;
  const method = req.method || 'GET';
  const body = method === 'GET' || method === 'DELETE' ? {} : await readBody(req);

  if (path === '/api/v1/auth/login' && method === 'POST') {
    sessionRole = 'admin';
    return send(res, 200, { token: 'local-audit', user: admin });
  }
  if (path === '/api/v1/auth/reseller/login' && method === 'POST') {
    sessionRole = 'reseller';
    return send(res, 200, { token: 'local-audit', user: resellerUser });
  }
  if (path === '/api/v1/auth/reseller/signup' && method === 'POST') {
    return send(res, 200, { ok: true, pending: true });
  }

  if (!authed(req)) return send(res, 401, { error: 'unauthorized', message: 'Session requise.' });

  if (path === '/api/v1/auth/me' || path === '/api/v1/me') {
    if (method === 'GET') return send(res, 200, { user: currentUser() });
  }
  if (path === '/api/v1/me/password' && method === 'POST') {
    return send(res, 200, { ok: true });
  }
  if (path === '/api/v1/stats/overview') {
    return send(res, 200, {
      customers: customers.length,
      devices: devices.length,
      licenses: licenses.length,
      active_licenses: licenses.filter((l) => l.status === 'active').length,
      expired_licenses: licenses.filter((l) => l.status === 'expired').length,
      expiring_7d: 1,
      apps: apps.length,
      revenue_30d_cents: 1998,
      resellers: resellers.length,
      credit_balance: currentUser().credit_balance,
    });
  }
  if (path === '/api/v1/backup') {
    return send(res, 200, { generatedAt: NOW, version: 1, tables: { note: ['jeu de données local'] } });
  }
  if (path === '/api/v1/apps') {
    if (method === 'GET') return send(res, 200, { items: apps });
    if (method === 'POST') {
      const id = 'app_' + (apps.length + 1);
      apps.push({
        id,
        name: body.name || 'Sans nom',
        package_name: body.package_name || 'com.example.app',
        primary_color: body.primary_color || '#D63A30',
        tagline: body.tagline || null,
        default_iptv_server: null,
        default_playlist_type: 'xtream',
        pricing_json: null,
        download_url: null,
        is_active: 1,
        created_at: Date.now(),
        updated_at: Date.now(),
      });
      return send(res, 200, { id });
    }
  }
  const appPatch = path.match(/^\/api\/v1\/apps\/([^/]+)$/);
  if (appPatch && method === 'PATCH') return send(res, 200, { updated: 1 });

  if (path === '/api/v1/servers') {
    if (method === 'GET') return send(res, 200, { items: servers });
    if (method === 'POST') {
      const id = 'srv_' + (servers.length + 1);
      servers.push({
        id,
        label: body.label || 'Serveur',
        url: body.url || 'https://exemple.invalid',
        position: servers.length + 1,
        enabled: body.enabled === false ? 0 : 1,
        created_at: Date.now(),
        updated_at: Date.now(),
      });
      return send(res, 200, { id });
    }
  }
  const srv = path.match(/^\/api\/v1\/servers\/([^/]+)$/);
  if (srv && method === 'PATCH') {
    const row = servers.find((s) => s.id === srv[1]);
    if (row && body.enabled !== undefined) row.enabled = body.enabled ? 1 : 0;
    if (row && body.label) row.label = body.label;
    if (row && body.url) row.url = body.url;
    return send(res, 200, { updated: 1 });
  }
  if (srv && method === 'DELETE') return send(res, 200, { deleted: 1 });

  if (path === '/api/v1/customers' && method === 'GET') {
    const q = (url.searchParams.get('q') || '').toLowerCase();
    const items = q
      ? customers.filter((c) => `${c.name} ${c.email} ${c.phone}`.toLowerCase().includes(q))
      : customers;
    return send(res, 200, { items });
  }
  if (path === '/api/v1/devices' && method === 'GET') {
    const q = (url.searchParams.get('q') || '').toLowerCase();
    const items = q
      ? devices.filter((d) => `${d.mac} ${d.label} ${d.customer_name}`.toLowerCase().includes(q))
      : devices;
    return send(res, 200, { items });
  }
  const devOverview = path.match(/^\/api\/v1\/devices\/([^/]+)\/overview$/);
  if (devOverview) {
    const id = decodeURIComponent(devOverview[1]);
    const d = devices.find((x) => x.id === id);
    return send(res, 200, {
      mac: d?.mac || 'MK:AA:BB:CC:DD:01',
      license: {
        status: 'active',
        plan: 'yearly',
        started_at: NOW - 30 * DAY,
        expires_at: NOW + 300 * DAY,
        auto_renew: 0,
      },
      presence: {
        online: true,
        ip: '203.0.113.10',
        country: 'FR',
        channel: '',
        last_seen: NOW - 60_000,
      },
      sources: [],
      localSources: [],
    });
  }
  const dev = path.match(/^\/api\/v1\/devices\/([^/]+)$/);
  if (dev && method === 'PATCH') {
    const row = devices.find((d) => d.id === dev[1]);
    if (row && body.block_status) row.block_status = body.block_status;
    return send(res, 200, { updated: 1, block_status: body.block_status || null });
  }
  if (dev && method === 'DELETE') return send(res, 200, { deleted: 1 });

  if (path === '/api/v1/licenses' && method === 'GET') return send(res, 200, { items: licenses });
  if (path === '/api/v1/licenses' && method === 'POST') {
    return send(res, 200, { id: 'lic_new', expires_at: Date.now() + 30 * DAY });
  }
  if (/^\/api\/v1\/licenses\/[^/]+\/renew$/.test(path) && method === 'POST') {
    return send(res, 200, { updated: 1, expires_at: Date.now() + 365 * DAY });
  }

  if (path === '/api/v1/resellers' && method === 'GET') return send(res, 200, { items: resellers });
  if (path === '/api/v1/resellers' && method === 'POST') {
    return send(res, 200, { id: 'rsl_new', credit_balance: body.credit_balance || 0 });
  }
  const rslCredits = path.match(/^\/api\/v1\/resellers\/([^/]+)\/credits$/);
  if (rslCredits && method === 'GET') {
    return send(res, 200, {
      items: [{
        id: 'cr_1', delta: 10, reason: 'issue', balance_after: 12,
        ref_device_mac: null, ref_license_id: null, note: 'démo', created_at: NOW - DAY,
      }],
    });
  }
  if (rslCredits && method === 'POST') {
    return send(res, 200, { credit_balance: 12 + (body.amount || 0), delta: body.amount || 0 });
  }
  const rsl = path.match(/^\/api\/v1\/resellers\/([^/]+)$/);
  if (rsl && method === 'GET') {
    return send(res, 200, resellers.find((r) => r.id === rsl[1]) || resellers[0]);
  }
  if (rsl && method === 'PATCH') return send(res, 200, { updated: 1 });

  if (path === '/api/v1/activate' && method === 'POST') {
    return send(res, 200, {
      ok: true,
      license_id: 'lic_new',
      device_id: 'dev_new',
      customer_id: 'cus_new',
      mac: body.mac || 'MK:AA:BB:CC:DD:09',
      plan: body.plan || 'yearly',
      expires_at: body.plan === 'lifetime' ? null : Date.now() + 365 * DAY,
      credits_charged: 0,
      credit_balance: currentUser().credit_balance,
      renewed: false,
    });
  }
  if (path.startsWith('/api/v1/sources/')) {
    if (method === 'GET') return send(res, 200, { mac: decodeURIComponent(path.split('/').pop()), source: null, sources: [] });
    if (method === 'PUT') return send(res, 200, { ok: true, mac: 'MK:AA:BB:CC:DD:01', count: 1 });
    if (method === 'DELETE') return send(res, 200, { ok: true, mac: 'MK:AA:BB:CC:DD:01' });
  }

  if (path === '/api/v1/announcements/settings') {
    if (method === 'GET') return send(res, 200, { enabled: announcementsEnabled });
    if (method === 'PUT') {
      announcementsEnabled = !!body.enabled;
      return send(res, 200, { ok: true, enabled: announcementsEnabled });
    }
  }
  if (path === '/api/v1/announcements') {
    if (method === 'GET') return send(res, 200, { items: announcements });
    if (method === 'POST') {
      const id = nextAnnId++;
      announcements.push({
        id,
        title: body.title || '',
        body: body.body || '',
        url: body.url || '',
        kind: body.kind || 'info',
        cta: body.cta || '',
        country: body.country || '',
        expires_at: Date.now() + DAY,
        active: 1,
        created_at: Date.now(),
      });
      return send(res, 200, { ok: true, id });
    }
    if (method === 'DELETE') {
      announcements = [];
      return send(res, 200, { ok: true });
    }
  }
  const ann = path.match(/^\/api\/v1\/announcements\/(\d+)$/);
  if (ann && method === 'DELETE') {
    announcements = announcements.filter((a) => String(a.id) !== ann[1]);
    return send(res, 200, { ok: true });
  }
  if (ann && method === 'PATCH') return send(res, 200, { ok: true, active: !!body.active });

  if (path === '/api/v1/home-layout' && method === 'GET') {
    return send(res, 200, { items: homeItems, version: 1 });
  }
  if (path === '/api/v1/home-layout' && method === 'PUT') {
    if (Array.isArray(body.items)) homeItems = body.items;
    return send(res, 200, { ok: true, items: homeItems, version: 2 });
  }
  if (path === '/api/v1/home-layout/history') return send(res, 200, { items: homeHistory });
  if (path === '/api/v1/home-layout/restore' && method === 'POST') return send(res, 200, { ok: true });

  if (path === '/api/v1/force-update' && method === 'GET') {
    return send(res, 200, { minBuildTs: forceMin, latestBuildTs: forceLatest });
  }
  if (path === '/api/v1/force-update' && method === 'POST') {
    forceMin = body.action === 'force' ? forceLatest : 0;
    return send(res, 200, { ok: true, minBuildTs: forceMin });
  }

  if (path === '/api/v1/featured' && method === 'GET') return send(res, 200, featured);
  if (path === '/api/v1/featured' && method === 'POST') {
    featured = { name: body.name || '', note: body.note || '' };
    return send(res, 200, { ok: true, ...featured });
  }

  if (path === '/api/v1/theme/automations' && method === 'GET') return send(res, 200, { rules: themeRules });
  if (path === '/api/v1/theme/automations' && method === 'PUT') {
    themeRules = Array.isArray(body.rules) ? body.rules : [];
    return send(res, 200, { ok: true, rules: themeRules });
  }
  if (path === '/api/v1/theme' && method === 'GET') return send(res, 200, theme);
  if (path === '/api/v1/theme' && method === 'PUT') {
    theme = { appName: body.appName || '', accent: body.accent || '', bg: body.bg || 'dark' };
    return send(res, 200, { ok: true, ...theme });
  }

  if (path === '/api/v1/audit-logs') {
    return send(res, 200, {
      items: [
        {
          id: 'aud_1', actor_type: 'admin', actor_id: 'usr_audit',
          action: 'theme.save', target_type: 'theme', target_id: 'mobile',
          before_json: null, after_json: null, created_at: NOW - 3600_000,
        },
        {
          id: 'aud_2', actor_type: 'reseller', actor_id: 'rsl_demo',
          action: 'action.inconnue', target_type: null, target_id: null,
          before_json: null, after_json: null, created_at: NOW - 7200_000,
        },
      ],
    });
  }
  if (path === '/api/v1/references') {
    return send(res, 200, {
      items: [{
        mac: 'MK:AA:BB:CC:DD:01',
        customer_name: 'Ada Martin',
        usernames: ['demo'],
        servers: ['https://exemple.invalid'],
        status: 'active',
        label: 'Salon',
        updated_at: NOW - DAY,
      }],
    });
  }
  if (path === '/api/v1/transfer' && method === 'POST') {
    return send(res, 200, {
      ok: true, old_mac: body.old_mac, new_mac: body.new_mac, moved_licenses: 1,
    });
  }
  if (path === '/api/v1/families' && method === 'GET') return send(res, 200, { items: families });
  if (path === '/api/v1/families' && method === 'POST') {
    const id = 'fam_' + (families.length + 1);
    const fam = {
      id, name: body.name || 'Famille',
      source: body.source ? { type: body.source.type, username: body.source.username, server_url: 'https://exemple.invalid' } : null,
      member_count: 0, created_at: Date.now(),
    };
    families.push(fam);
    familyMembers[id] = [];
    familyLinks[id] = [];
    return send(res, 200, { ok: true, family: fam });
  }
  const fam = path.match(/^\/api\/v1\/families\/([^/]+)$/);
  if (fam && method === 'GET') {
    const id = fam[1];
    return send(res, 200, {
      family: families.find((f) => f.id === id) || families[0],
      members: familyMembers[id] || [],
      links: familyLinks[id] || [],
    });
  }
  if (fam && method === 'DELETE') return send(res, 200, { ok: true });
  const famMember = path.match(/^\/api\/v1\/families\/([^/]+)\/members$/);
  if (famMember && method === 'POST') return send(res, 200, { ok: true, mac: body.mac });
  if (/^\/api\/v1\/families\/[^/]+\/members\//.test(path) && method === 'DELETE') {
    return send(res, 200, { ok: true });
  }
  const famLink = path.match(/^\/api\/v1\/families\/([^/]+)\/links$/);
  if (famLink && method === 'POST') {
    const link = { id: 'lnk_new', token: 'jeton-demo', label: body.label || null, created_at: Date.now() };
    return send(res, 200, link);
  }
  if (/^\/api\/v1\/families\/[^/]+\/links\//.test(path) && method === 'DELETE') {
    return send(res, 200, { ok: true });
  }

  if (path === '/api/v1/ad' && method === 'GET') return send(res, 200, ad);
  if (path === '/api/v1/ad' && method === 'PUT') {
    ad = { enabled: !!body.enabled, url: body.url || '', skip: body.skip ?? 5, freq: body.freq || 'daily' };
    return send(res, 200, { ok: true, ...ad });
  }
  if (path === '/api/v1/pricing' && method === 'GET') return send(res, 200, pricing);
  if (path === '/api/v1/pricing' && method === 'PUT') {
    pricing = { ...pricing, ...body };
    return send(res, 200, { ok: true, ...pricing });
  }
  if (path === '/api/v1/grant-trial-all' && method === 'POST') {
    return send(res, 200, { ok: true, days: body.days || 7, updated: 2 });
  }
  if (path === '/api/v1/feedback-prompt' && method === 'GET') return send(res, 200, feedbackPrompt);
  if (path === '/api/v1/feedback-prompt' && method === 'PUT') {
    feedbackPrompt = { enabled: !!body.enabled, message: body.message || '' };
    return send(res, 200, { ok: true, ...feedbackPrompt });
  }
  if (path === '/api/v1/feedback') return send(res, 200, { items: feedbackItems });
  if (path === '/api/v1/online') {
    return send(res, 200, {
      onlineCount: 1,
      todayCount: 2,
      byCountry: { FR: 1 },
      items: [{
        mac: 'MK:AA:BB:CC:DD:01',
        ip: '203.0.113.10',
        country: 'FR',
        lastSeen: NOW - 30_000,
        channel: '',
      }],
    });
  }
  if (path === '/api/v1/plan-costs' && method === 'GET') return send(res, 200, { items: planCosts });
  if (path === '/api/v1/plan-costs' && method === 'PUT') return send(res, 200, { updated: 1 });

  return send(res, 404, { error: 'not_found', message: `Route inconnue ${method} ${path}` });
});

server.listen(8787, '127.0.0.1', () => {
  process.stdout.write('mock-api listening on 127.0.0.1:8787\n');
});
