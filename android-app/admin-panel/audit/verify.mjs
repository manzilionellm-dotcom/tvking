// Recontrôle ciblé APRÈS correctifs. Échoue (code 1) si un défaut corrigé est encore là.
import { chromium } from 'playwright';
import { createRequire } from 'node:module';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const axePath = require.resolve('axe-core/axe.min.js');
const BASE = 'http://127.0.0.1:5173';
const OUT = '/opt/cursor/artifacts/panel-audit/after';
fs.mkdirSync(OUT, { recursive: true });

const fails = [];
function check(name, ok, detail) {
  const line = `${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`;
  process.stdout.write(line + '\n');
  if (!ok) fails.push(line);
}

const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
check('titre', (await page.title()) === 'The Few — Admin', await page.title());
const fav = await page.request.get(BASE + '/favicon.svg');
check('favicon svg', fav.headers()['content-type']?.includes('image/svg+xml'), fav.headers()['content-type']);

await page.fill('#login-password', 'x');
await page.fill('#login-id', '');
check('identifiant vide bloque le bouton', await page.locator('button[type="submit"]').isDisabled());

await page.getByRole('button', { name: /Revendeur/ }).click();
await page.getByRole('button', { name: /Créer un compte/ }).click();
await page.fill('#login-id', 'a@exemple.invalid');
await page.fill('#login-password', 'a');
await page.click('button[type="submit"]');
await page.waitForTimeout(300);
const signupTxt = await page.locator('form').innerText();
check('mot de passe court refusé', /4 caractères/.test(signupTxt) && page.url().includes('/login'), signupTxt.slice(0, 80));

await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
await page.fill('#login-id', 'admin');
await page.fill('#login-password', 'x');
await page.click('button[type="submit"]');
await page.waitForURL((u) => !u.pathname.endsWith('/login'));

await page.goto(BASE + '/control-center', { waitUntil: 'networkidle' });
const themeHref = await page.getByRole('link', { name: /Thèmes dynamiques/ }).getAttribute('href');
const autoHref = await page.getByRole('link', { name: /Automatisation/ }).getAttribute('href');
check('thème cliquable', themeHref === '/theme', themeHref);
check('automatisation cliquable', autoHref === '/theme', autoHref);
const chip = await page.evaluate(() => {
  const el = [...document.querySelectorAll('span')].find((s) => s.textContent.trim() === 'Actif' && s.className.includes('text-success'));
  if (!el) return null;
  const cs = getComputedStyle(el);
  let rule = false;
  for (const sheet of document.styleSheets) {
    try {
      for (const r of sheet.cssRules) if (r.selectorText && r.selectorText.includes('text-success')) rule = true;
    } catch { /* feuille externe */ }
  }
  return { color: cs.color, parent: getComputedStyle(el.parentElement).color, rule };
});
check('puce Actif verte', !!chip && chip.rule && chip.color !== chip.parent, JSON.stringify(chip));
await page.screenshot({ path: OUT + '/control-center.png', fullPage: true });

await page.goto(BASE + '/online', { waitUntil: 'networkidle' });
const onlineColor = await page.evaluate(() => {
  const el = document.querySelector('.text-3xl.font-bold.text-success');
  return el ? getComputedStyle(el).color : null;
});
check('compteur en ligne vert', onlineColor === 'rgb(63, 190, 124)', onlineColor);
await page.screenshot({ path: OUT + '/online.png', fullPage: true });

await page.goto(BASE + '/activations', { waitUntil: 'networkidle' });
const act = await page.locator('main').innerText();
check('statut en français', /actif/i.test(act) && /expiré/i.test(act) && !act.includes('Device MAC'), act.split('\n').filter((l) => /actif|expir|mac/i.test(l)).slice(0, 6).join(' | '));
check('libellé une MAC', act.includes('Activer une MAC'));

await page.setViewportSize({ width: 390, height: 844 });
await page.goto(BASE + '/activations', { waitUntil: 'networkidle' });
const clipped = await page.evaluate(() => {
  const t = document.querySelector('table');
  const wrap = t?.parentElement;
  if (!t || !wrap) return true;
  const ox = getComputedStyle(wrap).overflowX;
  return t.scrollWidth > wrap.clientWidth + 2 && ox !== 'auto' && ox !== 'scroll';
});
check('tableau activations défile', clipped === false);
await page.screenshot({ path: OUT + '/mobile-activations.png', fullPage: true });

await page.goto(BASE + '/resellers', { waitUntil: 'networkidle' });
const header = await page.evaluate(() => {
  const h = document.querySelector('header');
  return { client: h.clientWidth, scroll: h.scrollWidth };
});
check('en-tête revendeurs tient', header.scroll <= header.client + 2, JSON.stringify(header));
await page.setViewportSize({ width: 768, height: 1024 });
await page.goto(BASE + '/resellers', { waitUntil: 'networkidle' });
const headerTab = await page.evaluate(() => {
  const h = document.querySelector('header');
  return { client: h.clientWidth, scroll: h.scrollWidth };
});
check('en-tête revendeurs tablette', headerTab.scroll <= headerTab.client + 2, JSON.stringify(headerTab));
await page.setViewportSize({ width: 390, height: 844 });
await page.screenshot({ path: OUT + '/mobile-resellers.png', fullPage: true });

await page.goto(BASE + '/', { waitUntil: 'networkidle' });
await page.getByRole('button', { name: 'Menu' }).click();
const before = await page.locator('aside').nth(1).isVisible().catch(async () => {
  const n = await page.locator('aside').count();
  let v = 0;
  for (let i = 0; i < n; i++) if (await page.locator('aside').nth(i).isVisible()) v++;
  return v;
});
await page.keyboard.press('Escape');
await page.waitForTimeout(200);
let visible = 0;
const n = await page.locator('aside').count();
for (let i = 0; i < n; i++) if (await page.locator('aside').nth(i).isVisible()) visible++;
check('Échap ferme le menu', visible === 0, `avant=${before} visibles=${visible}`);
await page.screenshot({ path: OUT + '/mobile-menu-escape.png' });

await page.setViewportSize({ width: 1440, height: 900 });
const axeRoutes = ['/login', '/notifications', '/home-manager', '/theme', '/ad', '/tarifs', '/account'];
await page.evaluate(() => localStorage.clear());
for (const route of axeRoutes) {
  if (route !== '/login' && !(await page.evaluate(() => !!localStorage.getItem('auth_token')))) {
    await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
    await page.fill('#login-id', 'admin');
    await page.fill('#login-password', 'x');
    await page.click('button[type="submit"]');
    await page.waitForURL((u) => !u.pathname.endsWith('/login'));
  }
  if (route === '/login') await page.evaluate(() => localStorage.clear());
  await page.goto(BASE + route, { waitUntil: 'networkidle' });
  await page.addScriptTag({ path: axePath });
  const v = await page.evaluate(async () => {
    const r = await window.axe.run(document, {
      runOnly: { type: 'rule', values: ['label', 'select-name', 'button-name'] },
    });
    return r.violations.map((x) => x.id + ':' + x.nodes.length);
  });
  check(`axe ${route} noms`, v.length === 0, v.join(', ') || '0');
  if (route === '/login') {
    await page.goto(BASE + '/login', { waitUntil: 'networkidle' });
    await page.fill('#login-id', 'admin');
    await page.fill('#login-password', 'x');
    await page.click('button[type="submit"]');
    await page.waitForURL((u) => !u.pathname.endsWith('/login'));
  }
}

await browser.close();
process.stdout.write(fails.length ? `\n${fails.length} échec(s)\n` : '\nTout le recontrôle ciblé passe.\n');
process.exit(fails.length ? 1 : 0);
