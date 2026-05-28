"use client";

import { useEffect, useState } from "react";

const STORAGE_KEY = "chambre-rouge:credential-id";

function bufToB64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function b64ToBuf(b64: string): ArrayBuffer {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export default function AuthGate({ children }: { children: React.ReactNode }) {
  const [supported, setSupported] = useState<boolean | null>(null);
  const [platformAvailable, setPlatformAvailable] = useState<boolean | null>(null);
  const [hasCredential, setHasCredential] = useState(false);
  const [unlocked, setUnlocked] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const ok =
      typeof window !== "undefined" && !!window.PublicKeyCredential;
    setSupported(ok);
    if (!ok) return;
    setHasCredential(!!localStorage.getItem(STORAGE_KEY));
    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      .then(setPlatformAvailable)
      .catch(() => setPlatformAvailable(false));
  }, []);

  const register = async () => {
    setError(null);
    setBusy(true);
    try {
      const challenge = crypto.getRandomValues(new Uint8Array(32));
      const userId = crypto.getRandomValues(new Uint8Array(16));
      const cred = (await navigator.credentials.create({
        publicKey: {
          challenge,
          rp: { name: "Chambre Rouge" },
          user: {
            id: userId,
            name: "proprietaire@chambre-rouge.local",
            displayName: "Propriétaire",
          },
          pubKeyCredParams: [
            { type: "public-key", alg: -7 },
            { type: "public-key", alg: -257 },
          ],
          authenticatorSelection: {
            authenticatorAttachment: "platform",
            userVerification: "required",
            residentKey: "preferred",
          },
          timeout: 60_000,
          attestation: "none",
        },
      })) as PublicKeyCredential | null;
      if (!cred) throw new Error("Création annulée");
      localStorage.setItem(STORAGE_KEY, bufToB64(cred.rawId));
      setHasCredential(true);
      setUnlocked(true);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Impossible d'enregistrer l'empreinte.",
      );
    } finally {
      setBusy(false);
    }
  };

  const unlock = async () => {
    setError(null);
    setBusy(true);
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (!stored) throw new Error("Aucune empreinte configurée.");
      const challenge = crypto.getRandomValues(new Uint8Array(32));
      const cred = await navigator.credentials.get({
        publicKey: {
          challenge,
          allowCredentials: [{ id: b64ToBuf(stored), type: "public-key" }],
          userVerification: "required",
          timeout: 60_000,
        },
      });
      if (!cred) throw new Error("Authentification annulée.");
      setUnlocked(true);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Échec de l'authentification.",
      );
    } finally {
      setBusy(false);
    }
  };

  const reset = () => {
    localStorage.removeItem(STORAGE_KEY);
    setHasCredential(false);
    setUnlocked(false);
    setError(null);
  };

  if (unlocked) return <>{children}</>;

  return (
    <div className="relative flex w-full max-w-md flex-col items-center gap-6 rounded-3xl border border-red-900/40 bg-zinc-950/80 p-10 text-center shadow-[0_0_60px_-15px_rgba(220,38,38,0.5)]">
      <div className="absolute -top-5 -right-5 z-10 flex h-20 w-20 rotate-12 items-center justify-center rounded-full border-4 border-red-600 bg-black text-red-500 shadow-lg shadow-red-600/40">
        <div className="flex flex-col items-center leading-none">
          <span className="text-[10px] font-semibold tracking-widest text-red-400">
            ADULT
          </span>
          <span className="text-2xl font-black">+18</span>
        </div>
      </div>

      <div className="text-6xl">🔒</div>

      <div>
        <h1 className="text-3xl font-black tracking-tight text-zinc-100">
          Chambre <span className="text-red-500">Rouge</span>
        </h1>
        <p className="mt-2 text-sm text-zinc-400">
          Accès protégé par empreinte digitale.
        </p>
      </div>

      {supported === false && (
        <div className="rounded-xl border border-amber-700/60 bg-amber-950/40 px-4 py-3 text-sm text-amber-200">
          Ce navigateur ne supporte pas WebAuthn. Utilise un navigateur récent
          sur ton téléphone.
        </div>
      )}

      {supported && platformAvailable === false && (
        <div className="rounded-xl border border-amber-700/60 bg-amber-950/40 px-4 py-3 text-sm text-amber-200">
          Aucun capteur biométrique détecté sur cet appareil.
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-red-700/60 bg-red-950/50 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      )}

      {supported && (
        <div className="flex w-full flex-col gap-3">
          {hasCredential ? (
            <>
              <button
                type="button"
                onClick={unlock}
                disabled={busy}
                className="flex items-center justify-center gap-2 rounded-full bg-red-600 px-6 py-4 text-base font-bold uppercase tracking-wide text-white transition hover:bg-red-500 disabled:opacity-50"
              >
                <span className="text-xl">👆</span>
                {busy ? "Authentification..." : "Déverrouiller"}
              </button>
              <button
                type="button"
                onClick={reset}
                className="text-xs text-zinc-500 underline-offset-4 hover:underline"
              >
                Réinitialiser l&apos;empreinte
              </button>
            </>
          ) : (
            <button
              type="button"
              onClick={register}
              disabled={busy || platformAvailable === false}
              className="flex items-center justify-center gap-2 rounded-full bg-red-600 px-6 py-4 text-base font-bold uppercase tracking-wide text-white transition hover:bg-red-500 disabled:opacity-50"
            >
              <span className="text-xl">👆</span>
              {busy
                ? "Configuration..."
                : "Configurer l'empreinte digitale"}
            </button>
          )}
        </div>
      )}

      <p className="text-[11px] text-zinc-600">
        L&apos;empreinte est stockée localement sur ton appareil — elle ne quitte
        jamais ton téléphone.
      </p>
    </div>
  );
}
