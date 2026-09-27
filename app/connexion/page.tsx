"use client";

import { useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import AppOnlyNotice from "../components/site/AppOnlyNotice";

type Session = { email: string; at: string };

const KEY = "zuno_demo_session";

export default function ConnexionPage() {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [session, setSession] = useState<Session | null>(null);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) setSession(JSON.parse(raw));
    } catch {
      /* ignore */
    }
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch("/api/auth", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, mode }),
      });
      const data = await res.json();
      if (!res.ok) {
        setMsg(data.message || "Erreur");
        return;
      }
      const s: Session = { email: data.email, at: new Date().toISOString() };
      localStorage.setItem(KEY, JSON.stringify(s));
      setSession(s);
      setMsg(data.message);
    } catch {
      setMsg("Erreur réseau");
    } finally {
      setBusy(false);
    }
  }

  function logout() {
    localStorage.removeItem(KEY);
    setSession(null);
    setMsg(null);
  }

  return (
    <div className="zuno-page mx-auto max-w-md px-4 py-14 sm:px-6">
      <h1 className="text-center text-3xl font-bold text-white">Connexion</h1>
      <p className="mt-2 text-center text-sm text-white/45">
        Espace compte démo (stub). Auth.js / Clerk pourront remplacer ce flux.
      </p>
      <div className="mx-auto mt-5 max-w-xl"><AppOnlyNotice variant="banner" /></div>

      {session ? (
        <div className="zuno-card mt-8 rounded-2xl border border-white/10 bg-white/[0.03] p-6">
          <h2 className="text-lg font-semibold text-white">Mon abonnement</h2>
          <p className="mt-2 text-sm text-white/60">Connecté : {session.email}</p>
          <p className="mt-1 text-xs text-white/35">
            Stub local — aucun abonnement Stripe lié pour l’instant.
          </p>
          <div className="mt-6 flex flex-col gap-2">
            <Link href="/forfaits" className="rounded-xl bg-[#2563eb] px-4 py-3 text-center text-sm font-semibold text-white">
              Voir les forfaits
            </Link>
            <Link href="/activer" className="rounded-xl border border-white/15 px-4 py-3 text-center text-sm text-white/80">
              Activer mon appareil
            </Link>
            <button type="button" onClick={logout} className="mt-2 text-sm text-white/40 hover:text-white/70">
              Se déconnecter
            </button>
          </div>
        </div>
      ) : (
        <form onSubmit={onSubmit} className="zuno-card mt-8 flex flex-col gap-4 rounded-2xl border border-white/10 bg-white/[0.03] p-6">
          <div className="flex rounded-xl border border-white/10 p-1">
            <button
              type="button"
              onClick={() => setMode("login")}
              className={`flex-1 rounded-lg py-2 text-sm font-medium ${mode === "login" ? "bg-white/10 text-white" : "text-white/45"}`}
            >
              Connexion
            </button>
            <button
              type="button"
              onClick={() => setMode("register")}
              className={`flex-1 rounded-lg py-2 text-sm font-medium ${mode === "register" ? "bg-white/10 text-white" : "text-white/45"}`}
            >
              Inscription
            </button>
          </div>
          <label className="text-sm text-white/60">
            E-mail
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-white outline-none focus:border-[#3b82f6]/70"
            />
          </label>
          <label className="text-sm text-white/60">
            Mot de passe
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-white outline-none focus:border-[#3b82f6]/70"
            />
          </label>
          {msg && <p className="text-sm text-amber-200/90">{msg}</p>}
          <button
            type="submit"
            disabled={busy}
            className="rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#1d4ed8] py-3 font-semibold text-white disabled:opacity-50"
          >
            {busy ? "…" : mode === "register" ? "Créer mon compte" : "Se connecter"}
          </button>
        </form>
      )}
    </div>
  );
}
