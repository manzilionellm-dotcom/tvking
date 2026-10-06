// Parcours automatisé du panel (Playwright + Chrome).
// Prérequis : mock-api.mjs sur :8787 et `npm run dev` sur :5173.
// Ne journalise aucun mot de passe ni jeton.

import { chromium } from 'playwright';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const axePath = require.resolve('axe-core/axe.min.js');

const BASE = process.env.PANEL_URL || 'http://127.0.0.1:5173';
const OUT = process.env.AUDIT_OUT || '/opt/cursor/artifacts/panel-audit';
fs.mkdirSync(OUT, { recursive: true });

const ROUTES = [
  '/',
  '/activate',
  '/notifications',
  '/control-center',
  '/home-manager',
  '/force-update',
  '/online',
  '/featured',
  '/theme',
  '/ad',
  '/tarifs',
  '/reviews',
  '/customers',
  '/devices',
  '/apps',
  '/servers',
  '/activations',
  '/resellers',
  '/account',
  '/history',
  '/references',
  '/transfer',
  '/families',
];

const VIEWPORTS = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'mobile', width: 390, height: 844 },
];

function slug(s) {
  return s.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '') || 'home';
}

async function shot(page, name) {
  const file = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: file, fullPage: true });
  return file;
}

async function contrastSamples(page) {
  return page.evaluate(() => {
    function lin(c) {
      c = c / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    function lum(rgb) {
      return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]);
    }
    function parse(c) {
      const m = c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
      if (!m) return null;
      return [Number(m[1]), Number(m[2]), Number(m[3]), c.includes('rgba') ? Number(c.split(',')[3]) : 1];
    }
    function bgOf(el) {
      let n = el;
      while (n) {
        const c = parse(getComputedStyle(n).backgroundColor);
        if (c && c[3] > 0.5) return c;
        n = n.parentElement;
      }
      return [14, 14, 18, 1];
    }
    const seen = new Map();
    const nodes = document.querySelectorAll('body *');
    for (const el of nodes) {
      const text = (el.childNodes && [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim().length > 0));
      if (!text) continue;
      const cs = getComputedStyle(el);
      if (cs.visibility === 'hidden' || cs.display === 'none') continue;
      const fg = parse(cs.color);
      if (!fg) continue;
      const bg = bgOf(el);
      const size = parseFloat(cs.fontSize);
      const ratio = (Math.max(lum(fg), lum(bg)) + 0.05) / (Math.min(lum(fg), lum(bg)) + 0.05);
      const sample = (el.textContent || '').trim().slice(0, 40);
      const key = `${cs.color}|${size}|${ratio.toFixed(2)}`;
      if (!seen.has(key)) {
        seen.set(key, {
          sample, color: cs.color, size, ratio: Number(ratio.toFixed(2)),
          weight: cs.fontWeight, cls: (el.className || '').toString().slice(0, 80),
        });
      }
    }
    return [...seen.values()].filter((x) => x.ratio < 4.5 && x.size < 18).sort((a, b) => a.ratio - b.ratio);
  });
}

async function successColor(page) {
  return page.evaluate(() => {
    const el = document.querySelector('[class*="text-success"]');
    if (!el) return { found: false };
    const cs = getComputedStyle(el);
    const parent = getComputedStyle(el.parentElement || document.body);
    const rule = [...document.styleSheets].some((sheet) => {
      try {
        return [...sheet.cssRules].some((r) => r.selectorText && r.selectorText.includes('text-success'));
      } catch { return false; }
    });
    return {
      found: true,
      text: (el.textContent || '').trim().slice(0, 60),
      className: el.className,
      color: cs.color,
      parentColor: parent.color,
      sameAsParent: cs.color === parent.color,
      stylesheetHasTextSuccess: rule,
    };
  });
}

async function tableOverflow(page) {
  return page.evaluate(() => {
    const tables = [...document.querySelectorAll('table')];
    return tables.map((t) => {
      const wrap = t.parentElement;
      const r = t.getBoundingClientRect();
      return {
        headers: [...t.querySelectorAll('th')].map((th) => th.textContent.trim()),
        tableWidth: Math.round(t.scrollWidth),
        wrapWidth: wrap ? Math.round(wrap.clientWidth) : null,
        clipped: wrap ? t.scrollWidth > wrap.clientWidth + 2 && getComputedStyle(wrap).overflowX !== 'auto' && getComputedStyle(wrap).overflowX !== 'scroll' : false,
        viewport: Math.round(r.width),
      };
    });
  });
}

async function headerOverflow(page) {
  return page.evaluate(() => {
    const h = document.querySelector('header');
    if (!h) return null;
    return {
      client: h.clientWidth,
      scroll: h.scrollWidth,
      overflow: h.scrollWidth > h.clientWidth + 2,
    };
  });
}

const report = {
  startedAt: new Date().toISOString(),
  base: BASE,
  console: [],
  network: [],
  pages: [],
  interactions: [],
  login: {},
  axe: [],
};

const browser = await chromium.launch({
  channel: 'chrome',
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

async function attach(page, tag) {
  page.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') {
      const text = msg.text();
      if (/password|token|authorization/i.test(text)) return;
      report.console.push({ tag, type: msg.type(), text: text.slice(0, 300) });
    }
  });
  page.on('pageerror', (err) => {
    report.console.push({ tag, type: 'pageerror', text: String(err).slice(0, 300) });
  });
  page.on('response', (resp) => {
    const status = resp.status();
    const u = resp.url();
    if (status >= 400 && !u.includes('fonts.g')) {
      report.network.push({ tag, status, url: u.replace(/Bearer[^&]*/g, '') });
    }
  });
}

async function login(page) {
  await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
  await page.fill('input:not([type="password"])', 'admin');
  await page.fill('input[type="password"]', 'x');
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => !u.pathname.endsWith('/login'), { timeout: 8000 });
}

// ---------- Login (déconnecté) ----------
{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await attach(page, 'login');
  await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
  await shot(page, 'login-desktop');

  const title = await page.title();
  const brand = await page.locator('h1').innerText();
  const submitDisabledEmpty = await page.locator('button[type="submit"]').isDisabled();

  await page.fill('input[type="password"]', 'x');
  await page.fill('input:not([type="password"])', '');
  const submitDisabledNoId = await page.locator('button[type="submit"]').isDisabled();
  let emptyIdResult = null;
  if (!submitDisabledNoId) {
    await page.click('button[type="submit"]');
    await page.waitForTimeout(500);
    emptyIdResult = { url: page.url() };
    // L'API fictive accepte n'importe quel identifiant : on note seulement
    // si le bouton a laissé partir un identifiant vide.
    emptyIdResult.leftLogin = !page.url().includes('/login');
  }

  async function freshLogin() {
    await page.evaluate(() => localStorage.clear());
    await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
  }

  // Retour login pour le mode revendeur / inscription.
  await freshLogin();
  await page.getByRole('button', { name: /Revendeur/ }).click();
  await page.getByRole('button', { name: /Créer un compte/ }).click();
  await shot(page, 'login-signup');
  const signupHtml = await page.locator('form').innerText();
  // Mot de passe d'un seul caractère : le bouton n'est bloqué que si le champ est vide.
  await page.fill('input:not([type="password"])', 'a@exemple.invalid');
  await page.fill('input[type="password"]', 'a');
  const signupShortEnabled = !(await page.locator('button[type="submit"]').isDisabled());

  // Clavier : Tab depuis le début du formulaire.
  await freshLogin();
  await page.locator('h1').focus().catch(() => {});
  const tabStops = [];
  for (let i = 0; i < 8; i++) {
    await page.keyboard.press('Tab');
    const info = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el) return null;
      const cs = getComputedStyle(el);
      return {
        tag: el.tagName,
        type: el.getAttribute('type'),
        text: (el.innerText || el.getAttribute('aria-label') || '').slice(0, 40),
        outline: cs.outlineStyle,
        outlineWidth: cs.outlineWidth,
        boxShadow: cs.boxShadow === 'none' ? 'none' : 'yes',
      };
    });
    tabStops.push(info);
  }

  // Labels associés ?
  const labelAssoc = await page.evaluate(() => {
    const labels = [...document.querySelectorAll('form label')];
    return labels.map((l) => ({
      text: l.textContent.trim().slice(0, 40),
      htmlFor: l.htmlFor || null,
      wrapsControl: !!l.querySelector('input,select,textarea'),
    }));
  });

  const favicon = report.network.filter((n) => n.url.includes('favicon'));

  report.login = {
    title,
    brand,
    submitDisabledEmpty,
    submitDisabledNoId,
    emptyIdLeftLogin: emptyIdResult?.leftLogin ?? null,
    signupShortEnabled,
    signupHasMinLengthHint: /4 caractère|au moins/i.test(signupHtml),
    tabStops,
    labelAssoc,
    favicon404: favicon,
    contrast: await contrastSamples(page),
  };
  await page.close();
}

// Lien revendeur dédié
{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await attach(page, 'login-mobile');
  await page.goto(BASE + '/login?revendeur', { waitUntil: 'networkidle' });
  await shot(page, 'login-mobile-revendeur');
  const adminTabVisible = await page.getByRole('button', { name: /^Admin$/ }).count();
  report.login.resellerOnlyHidesAdmin = adminTabVisible === 0;
  report.login.mobileContrast = await contrastSamples(page);
  await page.close();
}

// ---------- Pages connectées ----------
const context = await browser.newContext();
const page = await context.newPage();
await attach(page, 'app');
await page.setViewportSize({ width: 1440, height: 900 });
await login(page);
await shot(page, 'dashboard-desktop');

// Couleur « succès » sur le centre de contrôle (puce Actif).
await page.goto(BASE + '/control-center', { waitUntil: 'networkidle' });
report.successChip = await successColor(page);

// Carte Thèmes : lien ou non.
report.themeCard = await page.evaluate(() => {
  const cards = [...document.querySelectorAll('a, div')];
  const theme = [...document.querySelectorAll('body *')].find((el) =>
    el.childNodes.length && [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.includes('Thèmes dynamiques')));
  const card = theme?.closest('a');
  return {
    textFound: !!theme,
    isLink: !!card,
    href: card?.getAttribute('href') || null,
    status: theme?.closest('div')?.innerText?.includes('Phase 3') || false,
  };
});
await shot(page, 'control-center-desktop');

for (const vp of VIEWPORTS) {
  await page.setViewportSize({ width: vp.width, height: vp.height });
  for (const route of ROUTES) {
    const tag = `${vp.name}${route}`;
    const beforeConsole = report.console.length;
    const beforeNet = report.network.length;
    await page.goto(BASE + route, { waitUntil: 'networkidle' });
    await page.waitForTimeout(250);
    const file = await shot(page, `${vp.name}-${slug(route)}`);
    const h1 = await page.locator('h1').first().innerText().catch(() => '');
    const overflow = await tableOverflow(page);
    const header = await headerOverflow(page);
    const horizontal = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 2);
    report.pages.push({
      viewport: vp.name,
      route,
      h1,
      screenshot: file,
      newConsole: report.console.slice(beforeConsole),
      newNetwork: report.network.slice(beforeNet),
      tables: overflow,
      header,
      pageOverflowX: horizontal,
    });
  }
}

// Axe sur chaque page, desktop.
await page.setViewportSize({ width: 1440, height: 900 });
for (const route of ['/login', ...ROUTES]) {
  if (route === '/login') {
    await page.evaluate(() => localStorage.clear());
    await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
  } else {
    if (!(await page.evaluate(() => !!localStorage.getItem('auth_token')))) await login(page);
    await page.goto(BASE + route, { waitUntil: 'networkidle' });
  }
  await page.addScriptTag({ path: axePath });
  const violations = await page.evaluate(async () => {
    const r = await window.axe.run(document, {
      resultTypes: ['violations'],
      runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] },
    });
    return r.violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      help: v.help,
      nodes: v.nodes.length,
      sample: v.nodes.slice(0, 2).map((n) => ({ target: n.target, text: (n.failureSummary || '').slice(0, 180) })),
    }));
  });
  report.axe.push({ route, violations });
  if (route === '/login') await login(page);
}

// ---------- Boutons (desktop) ----------
await page.setViewportSize({ width: 1440, height: 900 });
page.on('dialog', async (d) => {
  report.interactions.push({ dialog: d.type(), message: d.message().slice(0, 120) });
  await d.dismiss();
});

async function clickables(page) {
  return page.evaluate(() => {
    const els = [...document.querySelectorAll('button, a[href]')];
    return els.map((el, i) => {
      el.setAttribute('data-audit-id', String(i));
      const r = el.getBoundingClientRect();
      return {
        id: String(i),
        tag: el.tagName,
        type: el.getAttribute('type'),
        text: (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim().slice(0, 80),
        href: el.getAttribute('href'),
        disabled: el.disabled || el.getAttribute('aria-disabled') === 'true',
        visible: r.width > 0 && r.height > 0,
      };
    });
  });
}

for (const route of ROUTES) {
  await page.goto(BASE + route, { waitUntil: 'networkidle' });
  await page.waitForTimeout(200);
  const seen = new Set();
  for (let guard = 0; guard < 40; guard++) {
    const items = await clickables(page);
    const it = items.find((x) => {
      if (!x.visible || x.disabled) return false;
      const label = x.text || x.href || x.tag;
      if (/déconnect|se déconnecter|sign out/i.test(label)) return false;
      if (seen.has(label + '|' + x.tag)) return false;
      return true;
    });
    if (!it) break;
    const label = it.text || it.href || it.tag;
    seen.add(label + '|' + it.tag);
    if (it.tag === 'A' && it.href && /^https?:/i.test(it.href)) {
      report.interactions.push({
        route, label, kind: 'external-link',
        href: it.href.replace(/https?:\/\/[^/\s]+/i, '[hôte]'),
      });
      continue;
    }
    if (it.tag === 'A' && it.href && it.href.startsWith('/')) {
      report.interactions.push({ route, label, kind: 'internal-link', href: it.href.split('?')[0] });
      continue;
    }
    const before = await page.locator('body').innerText();
    const urlBefore = page.url();
    try {
      await page.locator(`[data-audit-id="${it.id}"]`).click({ timeout: 2000 });
      await page.waitForTimeout(200);
    } catch (e) {
      report.interactions.push({ route, label, kind: 'click-error', error: String(e).slice(0, 160) });
      continue;
    }
    const urlAfter = page.url();
    const after = await page.locator('body').innerText();
    report.interactions.push({
      route, label,
      kind: before !== after || urlBefore !== urlAfter ? 'effect' : 'no-effect',
      urlChanged: urlBefore !== urlAfter,
    });
    if (!urlAfter.includes(route === '/' ? '5173/' : route)) {
      await page.goto(BASE + route, { waitUntil: 'networkidle' });
    } else {
      const close = page.getByRole('button', { name: /^(Fermer|Annuler)$/ });
      if (await close.count()) await close.first().click().catch(() => {});
    }
  }
}

// Formulaire transfert vide.
{
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(BASE + '/transfer', { waitUntil: 'networkidle' });
  const disabled = await page.locator('button[type="submit"]').isDisabled();
  await page.locator('button[type="submit"]').click();
  await page.waitForTimeout(200);
  const txt = await page.locator('main').innerText();
  report.transferEmpty = {
    buttonDisabledWhenEmpty: disabled,
    showsValidation: /invalide|MAC/i.test(txt),
  };
}

// Compte : confirmation vide.
{
  await page.goto(BASE + '/account', { waitUntil: 'networkidle' });
  const inputs = page.locator('input[type="password"]');
  await inputs.nth(0).fill('x');
  await inputs.nth(1).fill('abcd');
  const disabled = await page.locator('button[type="submit"]').isDisabled();
  await page.locator('button[type="submit"]').click();
  await page.waitForTimeout(200);
  const txt = await page.locator('main').innerText();
  report.accountConfirm = {
    enabledWithoutConfirm: !disabled,
    showsMismatch: /correspond pas/i.test(txt),
  };
}

// Menu mobile : Échap ferme-t-il le tiroir ?
{
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '/', { waitUntil: 'networkidle' });
  await page.getByRole('button', { name: 'Menu' }).click();
  const visibleCount = async () => {
    const n = await page.locator('aside').count();
    let v = 0;
    for (let i = 0; i < n; i++) if (await page.locator('aside').nth(i).isVisible()) v++;
    return { n, v };
  };
  const open = await visibleCount();
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  const after = await visibleCount();
  report.mobileMenu = {
    asideCount: open.n,
    visibleWhenOpen: open.v,
    visibleAfterEscape: after.v,
    escapeCloses: open.v > 0 && after.v === 0,
  };
  await shot(page, 'mobile-menu-after-escape');
}

await browser.close();

// Agrège les erreurs console uniques et les liens internes morts (route inconnue).
const known = new Set(['/', '/login', '/activate', '/playlists', ...ROUTES]);
const internal = report.interactions.filter((i) => i.kind === 'internal-link');
report.deadInternal = internal.filter((i) => i.href && !known.has(i.href.split('?')[0]) && !i.href.startsWith('/devices'));

const consoleUniq = [];
const seenC = new Set();
for (const c of report.console) {
  const k = c.type + c.text;
  if (seenC.has(k)) continue;
  seenC.add(k);
  consoleUniq.push(c);
}
report.consoleUnique = consoleUniq;

const noEffect = report.interactions.filter((i) => i.kind === 'no-effect');
report.noEffect = noEffect;

fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));
process.stdout.write(`wrote ${path.join(OUT, 'report.json')}\n`);
process.stdout.write(`pages ${report.pages.length} interactions ${report.interactions.length} console ${consoleUniq.length}\n`);
