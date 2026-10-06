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
import { ApiError, blackboxApi } from '@/lib/api';
import {
  BLACKBOX_POLL_MS,
  formatBlackBoxUpdated,
  normalizePanelMac,
} from '@/lib/blackbox';

export function BlackBoxPage({ onLogout }: { onLogout: () => void }) {
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
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
          <input
            value={mac}
            onChange={(e) => setMac(e.target.value)}
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
