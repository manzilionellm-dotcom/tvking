// =========================================================
//  activation.test.ts — un seul écran d'activation, un seul catalogue
// =========================================================
//  Défaut corrigé le 06/10/2026 : deux entrées de menu pour le même geste
//  (« Grande activation de toutes les applications », « Activation à
//  distance ») et trois listes de durées différentes ; le libellé anglais
//  et arabe était le texte français.
// =========================================================
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DEFAULT_PLAN, DEFAULT_RENEW_PLAN, PAID_PLANS, TRIAL_PLANS,
  activateButtonText, activationResultText, isTrialPlan, planCost, planLabel,
} from './activation.ts';

const here = dirname(fileURLToPath(import.meta.url));
const src = (rel: string) => readFileSync(join(here, '..', rel), 'utf8');

// Copie de planToDays (cloudflare/api_v1.js) : le Worker doit comprendre
// chaque identifiant proposé (sinon il retombe sur 30 jours en silence).
function workerPlanToDays(plan: string): number | null | 'inconnu' {
  const dm = /^trial_(\d+)d$/.exec(plan);
  if (dm) return Number(dm[1]);
  switch (plan) {
    case 'monthly': return 30;
    case 'quarterly': return 90;
    case 'biannual': return 180;
    case 'yearly': return 365;
    case 'lifetime': return null;
    default: return 'inconnu';
  }
}

test('chaque durée proposée est comprise par le Worker, avec la bonne durée', () => {
  const want: Record<string, number | null> = {
    trial_3d: 3, trial_7d: 7, trial_14d: 14, trial_30d: 30,
    monthly: 30, quarterly: 90, biannual: 180, yearly: 365, lifetime: null,
  };
  for (const p of [...TRIAL_PLANS, ...PAID_PLANS]) {
    assert.equal(workerPlanToDays(p.id), want[p.id], p.id);
  }
});

test('aucun libellé en double : « 30 j » d’essai ≠ « 1 mois » payé', () => {
  const labels = [...TRIAL_PLANS, ...PAID_PLANS].map((p) => p.label);
  assert.equal(new Set(labels).size, labels.length);
  assert.ok(TRIAL_PLANS.every((p) => isTrialPlan(p.id)));
  assert.ok(PAID_PLANS.every((p) => !isTrialPlan(p.id)));
});

test('défauts : essai 7 jours pour une box neuve, 1 an pour prolonger', () => {
  assert.equal(DEFAULT_PLAN, 'trial_7d');
  assert.ok(TRIAL_PLANS.some((p) => p.id === DEFAULT_PLAN));
  assert.equal(DEFAULT_RENEW_PLAN, 'yearly');
  assert.equal(planLabel('trial_7d'), 'Essai 7 j');
  assert.equal(planLabel('yearly'), '1 an');
});

test('prix dit avant le clic : essai gratuit, crédits du tarif, rien si inconnu', () => {
  const costs = [{ plan: 'yearly', credits: 2 }, { plan: 'lifetime', credits: 1 }];
  assert.equal(planCost('trial_30d', costs), 0);
  assert.equal(planCost('yearly', costs), 2);
  assert.equal(planCost('quarterly', costs), null);
  assert.equal(activateButtonText('trial_7d', 0, true), 'Activer · essai gratuit');
  assert.equal(activateButtonText('yearly', 2, true), 'Activer · 2 crédits');
  assert.equal(activateButtonText('lifetime', 1, true), 'Activer · 1 crédit');
  assert.equal(activateButtonText('yearly', 2, false), 'Activer');
  assert.equal(activateButtonText('quarterly', null, true), 'Activer');
});

test('phrase de résultat', () => {
  const f = (ms: number) => `J${ms}`;
  assert.equal(activationResultText('trial_7d', { plan: 'trial_7d', expires_at: 5 }, f), 'Essai gratuit jusqu’au J5.');
  assert.equal(activationResultText('yearly', { plan: 'yearly', expires_at: 9 }, f), 'Activée jusqu’au J9.');
  assert.equal(activationResultText('lifetime', { plan: 'lifetime', expires_at: null }, f), 'Activée à vie.');
});

test('menu : UNE entrée d’activation, plus d’« Activation à distance »', () => {
  const sidebar = src('components/Sidebar.tsx');
  const admin = sidebar.slice(0, sidebar.indexOf('RESELLER_NAV'));
  const reseller = sidebar.slice(sidebar.indexOf('RESELLER_NAV'));
  for (const nav of [admin, reseller]) {
    assert.equal((nav.match(/to: '\/activate'/g) || []).length, 1);
    assert.doesNotMatch(nav, /activation-distance|nav\.remoteActivate/);
  }
  // L'ancienne adresse mène au nouvel écran, MAC comprise.
  assert.match(src('App.tsx'), /path="\/activation-distance" element=\{<RedirectKeepQuery to="\/activate" \/>\}/);
});

test('libellés courts et vraiment traduits', () => {
  const i18n = src('lib/i18n.tsx');
  const m = /'nav\.activate': \{ fr: '([^']+)', en: '([^']+)', ar: '([^']+)' \}/.exec(i18n);
  assert.ok(m, 'nav.activate sur une ligne');
  const [, fr, en, ar] = m;
  assert.equal(fr, 'Activer une box');
  assert.notEqual(en, fr);
  assert.notEqual(ar, fr);
  assert.ok(fr.length <= 24, 'tient dans le menu d’un téléphone');
  // Texte affiché seulement : les commentaires d'historique (// …) peuvent
  // citer l'ancien nom.
  const shown = [i18n, src('pages/ChainesPage.tsx'), src('pages/ActivatePage.tsx')]
    .join('\n').split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  assert.doesNotMatch(shown, /Grande activation de toutes/);
});

test('menu : aucun titre de section ne répète une de ses entrées (fr, en, ar)', () => {
  const sidebar = src('components/Sidebar.tsx');
  const i18n = src('lib/i18n.tsx');
  const label = (key: string, lang: 'fr' | 'en' | 'ar'): string => {
    const line = i18n.split('\n').find((l) => l.includes(`'${key}':`));
    assert.ok(line, `libellé manquant : ${key}`);
    const m = new RegExp(`${lang}: '([^']+)'`).exec(line);
    assert.ok(m, `${key} sans ${lang}`);
    return m[1].toLowerCase();
  };
  // Découpe : chaque `titleKey` suivi de ses `key:` jusqu'au titre suivant.
  const parts = sidebar.split(/titleKey: '/).slice(1);
  assert.ok(parts.length >= 6);
  for (const part of parts) {
    const title = part.slice(0, part.indexOf("'"));
    const items = [...part.matchAll(/\{ key: '([^']+)'/g)].map((m) => m[1]);
    assert.ok(items.length >= 1, `${title} : section vide`);
    for (const lang of ['fr', 'en', 'ar'] as const) {
      for (const item of items) {
        assert.notEqual(label(title, lang), label(item, lang), `${title} › ${item} (${lang})`);
      }
    }
  }
});
