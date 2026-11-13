// =========================================================
//  BlackBoxPage — Boîte noire d'une box, par son adresse MAC
// =========================================================
//  Lionel colle la MAC. Le panel affiche le même journal que
//  Réglages → Boîte noire (lignes [SON], etc.), déjà filtré.
//  Bouton Copier. Heure de la dernière réception.
//  Tant que la page est ouverte, on relit toutes les 1,5 s :
//  le texte apparaît 1 à 2 secondes après que l'app l'a envoyé.
// =========================================================

import { TracePanel } from './TracePanel';
import { FormEvent, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { MacInput, initialMac } from '@/components/MacInput';
import { ApiError, blackboxApi } from '@/lib/api';
import {
  BLACKBOX_POLL_MS,
  formatBlackBoxUpdated,
  normalizePanelMac,
} from '@/lib/blackbox';
import { diagnoseBlackBox, type Finding } from '@/lib/blackboxDiagnosis';

export function BlackBoxPage({ onLogout }: { onLogout: () => void }) {
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(initialMac(sp.get('mac'), 'MK:'));
  const [active, setActive] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [updatedAt, setUpdatedAt] = useState(0);
  const [err, setErr] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [asking, setAsking] = useState(false);

  // Une MAC déjà dans l'adresse (?mac=) : on l'affiche tout de suite.
  useEffect(() => {
    const fromUrl = normalizePanelMac(sp.get('mac') || '');
    if (fromUrl) {
      setMac(fromUrl);
      setActive(fromUrl);
    }
  }, [sp]);

  useEffect(() => {
    if (!active) return;
    let alive = true;

    async function load() {
      try {
        const row = await blackboxApi.get(active!);
        if (!alive) return;
        setText(row.text || '');
        setUpdatedAt(row.updated_at || 0);
        setErr(null);
      } catch (e) {
        if (!alive) return;
        if (e instanceof ApiError && e.status === 401) {
          onLogout();
          return;
        }
        const msg = e instanceof ApiError ? e.message : 'Lecture impossible.';
        setErr(msg);
      }
    }

    // Première demande : la box renverra son journal à sa prochaine
    // lecture du statut (quelques secondes). Ensuite on ne fait que lire.
    blackboxApi.ask(active).catch(() => {});
    load();
    const timer = window.setInterval(load, BLACKBOX_POLL_MS);
    return () => {
      alive = false;
      window.clearInterval(timer);
    };
  }, [active, onLogout]);

  function submit(e: FormEvent) {
    e.preventDefault();
    const next = normalizePanelMac(mac);
    if (!next) {
      setErr('Adresse MAC attendue : MK:XX:XX:XX:XX:XX');
      setActive(null);
      setText('');
      setUpdatedAt(0);
      return;
    }
    setErr(null);
    setMac(next);
    setActive(next);
  }

  async function askAgain() {
    if (!active) return;
    setAsking(true);
    try {
      await blackboxApi.ask(active);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onLogout();
      else setErr(e instanceof ApiError ? e.message : 'Demande impossible.');
    } finally {
      setAsking(false);
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setErr('Copie impossible depuis ce navigateur. Sélectionne le texte à la main.');
    }
  }

  const when = formatBlackBoxUpdated(updatedAt);
  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Boîte noire"
      subtitle="Colle l'adresse MAC. Le journal technique de la box s'affiche ici, le même que dans Réglages."
      onLogout={onLogout}
    >
      <form onSubmit={submit} className="mb-4 flex max-w-3xl flex-wrap items-end gap-3">
        <div className="min-w-[240px] flex-1">
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Adresse MAC de la box
          </label>
          <MacInput
            value={mac}
            onValueChange={setMac}
            autoFocus
            placeholder="MK:1A:2B:3C:4D:5E"
            className={inputCls + ' font-mono'}
          />
        </div>
        <button
          type="submit"
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright"
        >
          Afficher
        </button>
      </form>

      {err && (
        <div className="mb-4 max-w-3xl rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">
          {err}
        </div>
      )}

      {active && (
        <div className="max-w-5xl">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <p className="font-mono text-xs text-accent">{active}</p>
            <p className="text-xs text-ink-tertiary">
              {when
                ? `Dernière mise à jour : ${when}`
                : 'Pas encore de journal reçu pour cette box.'}
            </p>
          </div>
          <DiagnosisPanel text={text} />
          <textarea
            readOnly
            value={text}
            spellCheck={false}
            placeholder="En attente du journal. L'application l'envoie à l'ouverture, puis régulièrement. Tu peux aussi le redemander."
            className="h-[60vh] w-full resize-y rounded-xl border border-white/10 bg-midnight p-4 font-mono text-xs leading-5 text-ink-primary outline-none"
          />
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={copy}
              disabled={!text}
              className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-40"
            >
              {copied ? 'Copié' : 'Copier'}
            </button>
            <button
              type="button"
              onClick={askAgain}
              disabled={asking}
              className="rounded-md border border-white/10 px-4 py-2 text-sm text-ink-secondary hover:text-ink-primary"
            >
              {asking ? 'Demande envoyée…' : 'Redemander à la box'}
            </button>
          </div>
          <p className="mt-3 text-xs text-ink-tertiary">
            Les adresses de flux, les mots de passe et les identifiants sont
            retirés avant l'envoi. La page se met à jour toute seule.
          </p>
        </div>
      )}
      <TracePanel initialQuery={active || ''} key={active || 'vide'} />
    </AppLayout>
  );
}

const TONE: Record<Finding['severity'], { color: string; label: string }> = {
  critical: { color: '#EB5757', label: 'Bloquant' },
  warning: { color: '#F2C94C', label: 'À surveiller' },
  info: { color: '#8FB4D6', label: 'Information' },
};

/// Le diagnostic lu dans le journal : la panne, pourquoi, quoi faire.
/// Rien ne s'affiche tant qu'aucun journal n'est reçu.
function DiagnosisPanel({ text }: { text: string }) {
  if (!text.trim()) return null;
  const d = diagnoseBlackBox(text);
  const now = d.findings.filter((f) => f.current);
  const before = d.findings.filter((f) => !f.current);
  return (
    <div className="mb-4 rounded-xl border border-white/10 bg-midnight p-4">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-sm font-semibold uppercase tracking-widest text-ink-secondary">Diagnostic automatique</h2>
        <p className="text-xs text-ink-tertiary">
          {d.version ? `Version ${d.version}` : 'Version inconnue'}
          {d.lastBoot ? ` · dernier démarrage ${d.lastBoot}` : ''}
          {` · ${d.lines} lignes lues`}
        </p>
      </div>
      {d.findings.length === 0 && (
        <p className="text-sm" style={{ color: '#6FCF97' }}>
          Aucune panne connue dans ce journal. Si le client a quand même un souci, lis les
          dernières lignes ci-dessous ou redemande le journal juste après le problème.
        </p>
      )}
      {now.length > 0 && <FindingList title="Depuis le dernier démarrage" items={now} />}
      {before.length > 0 && <FindingList title="Plus ancien (peut-être déjà réglé)" items={before} muted />}
    </div>
  );
}

function FindingList({ title, items, muted }: { title: string; items: Finding[]; muted?: boolean }) {
  return (
    <div className={muted ? 'mt-4 opacity-70' : ''}>
      <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">{title}</div>
      <ul className="space-y-3">
        {items.map((f) => {
          const tone = TONE[f.severity];
          return (
            <li key={f.id} className="rounded-lg border border-white/5 p-3" style={{ borderLeft: `3px solid ${tone.color}` }}>
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <strong className="text-sm text-ink-primary">{f.title}</strong>
                <span className="text-[10px] uppercase tracking-widest" style={{ color: tone.color }}>
                  {tone.label} · {f.count} ligne(s) · dernière {f.last}
                </span>
              </div>
              <p className="mt-1 text-xs text-ink-secondary">{f.why}</p>
              <p className="mt-1 text-xs text-ink-primary"><span className="text-ink-tertiary">À faire : </span>{f.action}</p>
              <p className="mt-2 break-all font-mono text-[10px] text-ink-tertiary">{f.evidence}</p>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
