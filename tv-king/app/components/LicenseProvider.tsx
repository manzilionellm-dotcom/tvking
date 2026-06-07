"use client";

// =========================================================
//  LicenseProvider.tsx — Contexte de licence / essai
// =========================================================
//  Au montage : récupère le MAC virtuel de l'installation et fait un
//  heartbeat (qui enregistre l'appareil dans le panel et démarre l'essai
//  7 jours). Expose l'état + un `refresh()` (bouton « J'ai payé »).
// =========================================================

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import {
  getOrCreateMac,
  heartbeat,
  fetchStatus,
  UNKNOWN_STATUS,
  type LicenseStatus,
} from "../lib/license";

interface LicenseContextValue {
  ready: boolean;
  mac: string;
  status: LicenseStatus;
  refresh: () => Promise<void>;
}

const LicenseContext = createContext<LicenseContextValue | null>(null);

export function LicenseProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [mac, setMac] = useState("");
  const [status, setStatus] = useState<LicenseStatus>(UNKNOWN_STATUS);

  useEffect(() => {
    let active = true;
    const id = getOrCreateMac();
    setMac(id);
    heartbeat(id).then((s) => {
      if (!active) return;
      setStatus(s);
      setReady(true);
    });
    return () => {
      active = false;
    };
  }, []);

  const refresh = useCallback(async () => {
    if (!mac) return;
    const s = await fetchStatus(mac);
    setStatus(s);
  }, [mac]);

  return (
    <LicenseContext.Provider value={{ ready, mac, status, refresh }}>
      {children}
    </LicenseContext.Provider>
  );
}

export function useLicense(): LicenseContextValue {
  const ctx = useContext(LicenseContext);
  if (!ctx) throw new Error("useLicense doit être utilisé dans LicenseProvider");
  return ctx;
}
