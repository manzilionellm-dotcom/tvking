"use client";

import { useState } from "react";
import { useI18n } from "../../i18n/provider";
import {
  buildBody,
  itemsOf,
  normalizeMac,
  outcomeOf,
  type ApiOutcome,
  type PublicItem,
} from "../../lib/self-source";

/*
 * « Activer ma liste » : le client entre la MAC de sa box et SON abonnement
 * (Xtream ou M3U). Envoi au panel Zuno via le relais du site
 * (app/api/self-source/[mac]/route.ts, cf. lib/self-source.ts) ; la
 * box l'installe d'elle-même en moins d'une minute. Aucune donnée n'est
 * stockée par ce site.
 */

type Kind = "xtream" | "m3u";

const field =
  "focusable w-full rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.75rem] text-[1.05rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)] outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)]";
const label = "mb-[0.35rem] block text-[0.95rem] font-semibold text-[var(--text-high)]";

export default function ActivatePage() {
  const { m } = useI18n();
  const a = m.activate;

  const [macInput, setMacInput] = useState("");
  const [kind, setKind] = useState<Kind>("xtream");
  const [name, setName] = useState("");
  const [server, setServer] = useState("");
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [items, setItems] = useState<PublicItem[] | null>(null);

  const say = (o: ApiOutcome | "network") =>
    setMsg(o === "ok" ? { ok: true, text: a.success } : { ok: false, text: a.errors[o] });

  const macOrError = (): string | null => {
    const mac = normalizeMac(macInput);
    if (!mac) say("mac");
    return mac;
  };

  const loadItems = async (mac: string) => {
    try {
      const r = await fetch(`/api/self-source/${encodeURIComponent(mac)}`);
      const body = await r.json().catch(() => ({}));
      const out = outcomeOf(r.status, body);
      if (out !== "ok") {
        setItems(null);
        say(out);
        return;
      }
      setItems(itemsOf(body));
    } catch {
      say("network");
    }
  };

  const onCheck = async () => {
    setMsg(null);
    const mac = macOrError();
    if (!mac) return;
    setMacInput(mac);
    setBusy(true);
    await loadItems(mac);
    setBusy(false);
  };

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    const mac = macOrError();
    if (!mac) return;
    const body = buildBody(
      kind === "xtream"
        ? { type: "xtream", label: name || a.namePlaceholder, server, username: user, password: pass }
        : { type: "m3u", label: name || a.namePlaceholder, url },
    );
    if (!body) {
      say("fields");
      return;
    }
    setMacInput(mac);
    setBusy(true);
    try {
      const r = await fetch(`/api/self-source/${encodeURIComponent(mac)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const res = await r.json().catch(() => ({}));
      const out = outcomeOf(r.status, res);
      say(out);
      if (out === "ok") {
        setPass(""); // jamais conservé à l'écran après envoi
        await loadItems(mac);
      }
    } catch {
      say("network");
    }
    setBusy(false);
  };

  const onDelete = async (id: string) => {
    const mac = normalizeMac(macInput);
    if (!mac) return;
    setBusy(true);
    try {
      const r = await fetch(
        `/api/self-source/${encodeURIComponent(mac)}?id=${encodeURIComponent(id)}`,
        { method: "DELETE" },
      );
      const res = await r.json().catch(() => ({}));
      if (outcomeOf(r.status, res) === "ok") {
        setMsg({ ok: true, text: a.deleted });
        await loadItems(mac);
      } else {
        say(outcomeOf(r.status, res));
      }
    } catch {
      say("network");
    }
    setBusy(false);
  };

  // Export statique GitHub Pages : pas de serveur, donc pas de relais vers le
  // panel → on renvoie vers « Mon espace » du panel (même fonction).
  if (process.env.NEXT_PUBLIC_LOCALE_IN_PATH === "1") {
    return (
      <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">{a.title}</h1>
        <p className="mb-[1.5rem] mt-[0.4rem] max-w-[46rem] text-[1.2rem] text-[var(--text-medium)]">{a.intro}</p>
        <a
          href="https://app.7themotion.com/mon-espace"
          data-focusable
          className="focusable inline-flex rounded-full px-[1.4rem] py-[0.85rem] text-[1.05rem] font-bold text-black"
          style={{ background: "var(--gold-grad)" }}
        >
          {a.submit}
        </a>
      </div>
    );
  }

  const tab = (k: Kind, text: string) => (
    <button
      type="button"
      data-focusable
      onClick={() => setKind(k)}
      aria-pressed={kind === k}
      className="focusable flex-1 rounded-[var(--radius)] px-[1rem] py-[0.7rem] text-[1rem] font-semibold outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)]"
      style={
        kind === k
          ? { background: "var(--gold-grad)", color: "#000" }
          : { background: "var(--surface-2)", color: "var(--text-high)" }
      }
    >
      {text}
    </button>
  );

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <p className="text-[0.8rem] font-semibold uppercase tracking-[0.3em] text-[var(--text-medium)]">{a.kicker}</p>
      <h1 className="font-display mt-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {a.title}
      </h1>
      <p className="mb-[2rem] mt-[0.4rem] max-w-[46rem] text-[1.2rem] text-[var(--text-medium)]">{a.intro}</p>

      <div className="grid max-w-[72rem] gap-[var(--gap)] md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
        <form
          onSubmit={onSubmit}
          className="rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-white/[0.03] p-[1.5rem]"
        >
          <label className={label} htmlFor="mac">{a.macLabel}</label>
          <div className="flex gap-[0.6rem]">
            <input
              id="mac"
              data-focusable
              value={macInput}
              onChange={(e) => setMacInput(e.target.value)}
              placeholder="MK:80:78:60:07:4F"
              autoComplete="off"
              spellCheck={false}
              dir="ltr"
              className={`${field} font-mono uppercase tracking-wider`}
            />
            <button
              type="button"
              data-focusable
              onClick={onCheck}
              disabled={busy}
              className="focusable shrink-0 rounded-[var(--radius)] border border-[var(--hairline)] px-[1rem] text-[0.95rem] font-semibold text-[var(--text-high)] outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)] disabled:opacity-50"
            >
              {a.macCheck}
            </button>
          </div>
          <p className="mb-[1.2rem] mt-[0.35rem] text-[0.85rem] text-[var(--text-disabled)]">{a.macHint}</p>

          <p className={label}>{a.typeLabel}</p>
          <div className="mb-[1.2rem] flex gap-[0.6rem]">
            {tab("xtream", a.xtream)}
            {tab("m3u", a.m3u)}
          </div>

          <label className={label} htmlFor="name">{a.nameLabel}</label>
          <input id="name" data-focusable value={name} onChange={(e) => setName(e.target.value)}
            placeholder={a.namePlaceholder} className={`${field} mb-[1rem]`} />

          {kind === "xtream" ? (
            <>
              <label className={label} htmlFor="server">{a.serverLabel}</label>
              <input id="server" data-focusable value={server} onChange={(e) => setServer(e.target.value)}
                placeholder={a.serverPlaceholder} inputMode="url" autoComplete="off" spellCheck={false} dir="ltr"
                className={`${field} mb-[1rem]`} />
              <div className="mb-[1rem] grid gap-[0.8rem] sm:grid-cols-2">
                <div>
                  <label className={label} htmlFor="user">{a.userLabel}</label>
                  <input id="user" data-focusable value={user} onChange={(e) => setUser(e.target.value)}
                    autoComplete="off" spellCheck={false} dir="ltr" className={field} />
                </div>
                <div>
                  <label className={label} htmlFor="pass">{a.passLabel}</label>
                  <input id="pass" data-focusable type="password" value={pass} onChange={(e) => setPass(e.target.value)}
                    autoComplete="new-password" dir="ltr" className={field} />
                </div>
              </div>
            </>
          ) : (
            <>
              <label className={label} htmlFor="url">{a.urlLabel}</label>
              <input id="url" data-focusable value={url} onChange={(e) => setUrl(e.target.value)}
                placeholder={a.urlPlaceholder} inputMode="url" autoComplete="off" spellCheck={false} dir="ltr"
                className={`${field} mb-[1rem]`} />
            </>
          )}

          <button
            type="submit"
            data-focusable
            disabled={busy}
            className="focusable mt-[0.4rem] w-full rounded-full px-[1.4rem] py-[0.85rem] text-[1.05rem] font-bold text-black outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)] disabled:opacity-60"
            style={{ background: "var(--gold-grad)" }}
          >
            {busy ? a.sending : a.submit}
          </button>
          <p className="mt-[0.7rem] text-[0.85rem] text-[var(--text-disabled)]">{a.privacy}</p>

          {msg && (
            <p
              role="status"
              className="mt-[1rem] rounded-[var(--radius)] px-[1rem] py-[0.75rem] text-[1rem] font-semibold"
              style={
                msg.ok
                  ? { background: "rgba(88,201,163,0.14)", color: "var(--sport)" }
                  : { background: "rgba(229,86,91,0.14)", color: "var(--live)" }
              }
            >
              {msg.text}
            </p>
          )}
        </form>

        <section className="rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-white/[0.03] p-[1.5rem]">
          <h2 className="font-display text-[1.6rem] font-bold text-[var(--text-high)]">{a.myLists}</h2>
          {items === null || items.length === 0 ? (
            <p className="mt-[0.6rem] text-[1rem] text-[var(--text-medium)]">{a.none}</p>
          ) : (
            <ul className="mt-[0.8rem] space-y-[0.6rem]">
              {items.map((it, i) => (
                <li key={it.id ?? i} className="flex items-center gap-[0.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.7rem]">
                  <span className="rounded-md bg-white/10 px-[0.45rem] py-[0.1rem] text-[0.75rem] font-bold uppercase text-[var(--gold)]">
                    {it.type === "xtream" ? "Xtream" : "M3U"}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[1rem] font-semibold text-[var(--text-high)]">{it.label}</span>
                    <span className="block truncate text-[0.85rem] text-[var(--text-medium)]" dir="ltr">
                      {it.username ? `${it.username} · ` : ""}
                      {hostOf(it.server_url ?? it.m3u_url)}
                    </span>
                  </span>
                  {it.locked ? (
                    <span className="text-[0.8rem] text-[var(--text-disabled)]">{a.locked}</span>
                  ) : it.id ? (
                    <button
                      type="button"
                      data-focusable
                      onClick={() => onDelete(it.id!)}
                      disabled={busy}
                      className="focusable rounded-[var(--radius)] px-[0.7rem] py-[0.35rem] text-[0.85rem] font-semibold text-[var(--live)] outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)]"
                    >
                      {a.delete}
                    </button>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}

/** Hôte seul (jamais l'URL complète : elle contient souvent le mot de passe). */
function hostOf(u: string | null): string {
  if (!u) return "";
  try {
    return new URL(u).host;
  } catch {
    return "";
  }
}
