import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import { Alert } from '@/components/ui';
import {
  sourcesApi, userCan, getCurrentUser,
  type DeviceSource, type DeviceSourceInput, ApiError,
} from '@/lib/api';
import { isValidMac, normalizeMac } from '@/lib/utils';

// Écran LISTE DE CHAÎNES — séparé de l'activation.
// Enregistrer un lien n'appelle PAS /api/v1/activate.
// Le serveur n'a pas de case « seulement le lien » : il remplace toute
// la liste poussée par le panel. On relit d'abord, on ne change que le
// lien, et on renvoie le reste tel quel. Les listes ajoutées par le
// client sur sa télé (origin = self) sont remises par le serveur.

type Kept = DeviceSource & { origin?: string | null };

function panelSources(list: Kept[] | undefined): Kept[] {
  return (list || []).filter((s) => s.origin !== 'self');
}

function toInput(s: Kept): DeviceSourceInput {
  if (s.type === 'm3u') {
    return { type: 'm3u', m3u_url: s.m3u_url || '', label: s.label ?? null, epg_url: s.epg_url ?? null };
  }
  return {
    type: 'xtream',
    label: s.label ?? null,
    server_url: s.server_url ?? null,
    username: s.username ?? null,
    password: s.password ?? null,
    epg_url: s.epg_url ?? null,
  };
}

export function ChainesPage({ onLogout }: { onLogout: () => void }) {
  const canPush = userCan(getCurrentUser(), 'sources');
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [link, setLink] = useState('');
  const [hasLink, setHasLink] = useState(false);
  const [otherCount, setOtherCount] = useState(0);
  const [looking, setLooking] = useState(false);
  // Vrai seulement après une lecture réussie de CETTE mac. Sans ça, un
  // enregistrement trop tôt remplacerait les autres listes par le seul lien.
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  // Sources déjà poussées, hors lien. Gardées en mémoire seulement pour
  // les renvoyer telles quelles. Jamais affichées, jamais journalisées.
  const keptRef = useRef<DeviceSourceInput[]>([]);

  const macOk = isValidMac(mac);

  useEffect(() => {
    setLoaded(false);
    setHasLink(false);
    setOtherCount(0);
    keptRef.current = [];
    if (!macOk || !canPush) return;
    let cancel = false;
    const m = normalizeMac(mac);
    const timer = setTimeout(() => {
      setLooking(true);
      sourcesApi.get(m)
        .then((r) => {
          if (cancel) return;
          const panel = panelSources(r.sources as Kept[] | undefined);
          const others = panel.filter((s) => s.type !== 'm3u');
          keptRef.current = others.map(toInput);
          setHasLink(panel.some((s) => s.type === 'm3u'));
          setOtherCount(others.length);
          setErr(null);
          setLoaded(true);
        })
        .catch((e) => {
          if (cancel) return;
          keptRef.current = [];
          setHasLink(false);
          setOtherCount(0);
          setLoaded(false);
          if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
          // 404 = aucune liste pour cette box. On peut en enregistrer une.
          if (e instanceof ApiError && e.status === 404) {
            setLoaded(true);
            return;
          }
          setErr(e instanceof ApiError ? e.message : 'Impossible de lire la liste de cette box.');
        })
        .finally(() => { if (!cancel) setLooking(false); });
    }, 400);
    return () => { cancel = true; clearTimeout(timer); };
  }, [mac, macOk, canPush, onLogout]);

  async function save(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    setOk(null);
    const m = normalizeMac(mac);
    if (!isValidMac(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      return;
    }
    if (!loaded) {
      setErr('Attends que l’état de cette box soit lu, puis réessaie.');
      return;
    }
    const url = link.trim();
    if (!url) {
      setErr('Colle le lien de la liste avant d’enregistrer.');
      return;
    }
    const next = [...keptRef.current, { type: 'm3u' as const, m3u_url: url }];
    if (next.length > 3) {
      setErr('Cette box a déjà 3 listes. Retire-en une sur la fiche appareil avant d’en ajouter une.');
      return;
    }
    setBusy(true);
    try {
      await sourcesApi.setMany(m, next);
      setLink('');
      setHasLink(true);
      setOk('Lien enregistré. L’activation de l’application n’a pas été modifiée.');
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally {
      setBusy(false);
    }
  }

  async function removeLink() {
    setErr(null);
    setOk(null);
    const m = normalizeMac(mac);
    if (!isValidMac(m) || !hasLink) return;
    const onlyLink = keptRef.current.length === 0;
    const okConfirm = await confirmAction({
      title: 'Retirer le lien de cette box ?',
      message: onlyLink
        ? 'Le lien sera retiré. L’activation ne change pas. Si le client avait aussi ajouté une liste depuis sa télé, le serveur peut l’effacer en même temps : il n’a pas de bouton « retirer seulement ce lien ».'
        : 'Le lien sera retiré. L’autre liste déjà en place, et l’activation, ne changent pas.',
      confirmLabel: 'Retirer le lien',
      danger: true,
    });
    if (!okConfirm) return;
    setBusy(true);
    try {
      if (onlyLink) await sourcesApi.clear(m);
      else await sourcesApi.setMany(m, keptRef.current);
      setHasLink(false);
      setLink('');
      setOk('Lien retiré. L’activation de l’application n’a pas été modifiée.');
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Retrait impossible.');
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/10 bg-slate px-3 py-2.5 text-sm outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';

  return (
    <AppLayout
      title="Liste de chaînes"
      subtitle="Ajoute ou change le lien. Ça n’active pas l’application, et ça ne change pas la durée."
      onLogout={onLogout}
    >
      {!canPush && (
        <Alert>Ton compte ne peut pas modifier la liste de chaînes.</Alert>
      )}

      <div className="grid max-w-3xl gap-6">
        <form onSubmit={save} className="space-y-4 rounded-xl border border-white/10 bg-midnight p-6">
          <h2 className="text-base font-semibold">Lien de la liste</h2>
          <p className="text-sm leading-relaxed text-ink-secondary">
            Pour activer ou désactiver l’application, ou changer la durée, va sur{' '}
            <Link to="/activate" className="font-medium text-accent-bright underline-offset-2 hover:underline">
              Grande activation de toutes les applications
            </Link>.
          </p>

          <div>
            <label htmlFor="chaines-mac" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Adresse MAC de la box
            </label>
            <input
              id="chaines-mac"
              value={mac}
              onChange={(e) => { setMac(e.target.value); setOk(null); }}
              onBlur={() => setMac((v) => normalizeMac(v))}
              autoFocus
              autoComplete="off"
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls + ' font-mono'}
            />
          </div>

          <div className="rounded-lg border border-white/10 bg-obsidian px-4 py-3 text-sm">
            {looking && <p className="text-ink-secondary">Recherche…</p>}
            {!looking && !macOk && <p className="text-ink-secondary">Entre une MAC complète pour voir si un lien est déjà là.</p>}
            {!looking && macOk && hasLink && (
              <p className="font-medium text-ink-primary">Un lien est déjà enregistré pour cette box.</p>
            )}
            {!looking && macOk && !hasLink && (
              <p className="text-ink-secondary">Aucun lien enregistré pour cette box.</p>
            )}
            {!looking && otherCount > 0 && (
              <p className="mt-1 text-ink-secondary">
                Une autre liste est aussi en place. Elle sera conservée.
              </p>
            )}
          </div>

          <div>
            <label htmlFor="chaines-lien" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Nouveau lien
            </label>
            <input
              id="chaines-lien"
              value={link}
              onChange={(e) => setLink(e.target.value)}
              autoComplete="off"
              spellCheck={false}
              placeholder="Colle le lien de la liste ici"
              className={inputCls + ' font-mono'}
            />
          </div>

          {err && <Alert>{err}</Alert>}
          {ok && <Alert tone="ok">{ok}</Alert>}

          <div className="flex flex-col gap-2 sm:flex-row">
            <button
              type="submit"
              disabled={!canPush || busy || looking || !loaded || !macOk || !link.trim()}
              className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busy ? 'Enregistrement…' : hasLink ? 'Changer le lien' : 'Enregistrer le lien'}
            </button>
            <button
              type="button"
              onClick={removeLink}
              disabled={!canPush || busy || looking || !loaded || !macOk || !hasLink}
              className="rounded-md border border-white/15 px-4 py-2.5 text-sm font-medium text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Retirer le lien
            </button>
          </div>
        </form>
      </div>
    </AppLayout>
  );
}
