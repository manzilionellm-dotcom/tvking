"use client";

// =========================================================
//  preferences.tsx — Profils & réglages d'accessibilité
// =========================================================
//  Source unique de vérité pour TOUT ce qui adapte l'expérience :
//    - profil (Senior / Enfants / Standard)
//    - taille de l'UI (--ui-scale), overscan (--safe-scale)
//    - contraste élevé, réduction des animations, narration vocale
//    - mode « repos des yeux », édition VIP
//
//  Le provider applique ces réglages au <html> via des variables CSS et
//  des attributs data-* (lus par globals.css). Persistance localStorage.
//
//  IMPORTANT (« personne n'est perdu ») : tant qu'aucun profil n'est
//  choisi (profile === null), l'app affiche l'écran de sélection de
//  profil. Une fois choisi, c'est persisté et modifiable dans Réglages.
// =========================================================

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { narration } from "./narration";
import { sound } from "./sound";

export type ProfileId = "senior" | "enfants" | "standard";

export interface Preferences {
  /// null = écran de choix de profil au premier lancement.
  profile: ProfileId | null;
  uiScale: number; // multiplie la taille globale
  safeScale: number; // overscan (zone de sécurité TV)
  highContrast: boolean;
  reducedMotion: boolean;
  narration: boolean;
  eyeRest: boolean; // mode « repos des yeux »
  vip: boolean; // édition VIP / premium
  // --- Couche futuriste (chaque option désactivable) ---
  ambilight: boolean; // lueur de fond adaptative
  parallax: boolean; // légère profondeur 3D au focus
  soundCues: boolean; // petits retours sonores (WebAudio)
  voice: boolean; // recherche / commande vocale
}

/// Réglages par défaut appliqués QUAND on choisit un profil. Ils restent
/// modifiables ensuite individuellement dans Réglages.
const PROFILE_DEFAULTS: Record<ProfileId, Partial<Preferences>> = {
  // Senior : tout plus grand, contraste max, animations réduites,
  // narration active, moins d'éléments (géré côté pages).
  senior: {
    uiScale: 1.3,
    highContrast: true,
    reducedMotion: true,
    narration: true,
    eyeRest: true,
    parallax: false, // moins de mouvement = plus reposant
    soundCues: true, // un retour sonore aide en basse vision
  },
  // Enfants : un peu plus grand, navigation guidée, narration active.
  enfants: {
    uiScale: 1.15,
    highContrast: false,
    reducedMotion: false,
    narration: true,
    eyeRest: false,
  },
  // Standard : expérience complète, options off par défaut.
  standard: {
    uiScale: 1,
    highContrast: false,
    reducedMotion: false,
    narration: false,
    eyeRest: false,
  },
};

const DEFAULTS: Preferences = {
  profile: null,
  uiScale: 1,
  safeScale: 1,
  highContrast: false,
  reducedMotion: false,
  narration: false,
  eyeRest: false,
  vip: false,
  ambilight: true,
  parallax: true,
  soundCues: false,
  voice: true,
};

const STORAGE_KEY = "tvking.prefs.v1";

interface PreferencesContextValue {
  prefs: Preferences;
  ready: boolean; // true une fois le localStorage lu (évite le flash SSR)
  setProfile: (p: ProfileId) => void;
  update: (patch: Partial<Preferences>) => void;
  reset: () => void;
}

const PreferencesContext = createContext<PreferencesContextValue | null>(null);

export function PreferencesProvider({ children }: { children: ReactNode }) {
  const [prefs, setPrefs] = useState<Preferences>(DEFAULTS);
  const [ready, setReady] = useState(false);

  // 1) Au montage : on lit le localStorage (côté client uniquement).
  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as Partial<Preferences>;
        setPrefs({ ...DEFAULTS, ...parsed });
      }
    } catch {
      /* localStorage indisponible → on garde les défauts */
    }
    setReady(true);
  }, []);

  // 2) À chaque changement : on applique au <html> + on persiste.
  useEffect(() => {
    if (!ready) return;
    const root = document.documentElement;
    root.style.setProperty("--ui-scale", String(prefs.uiScale));
    root.style.setProperty("--safe-scale", String(prefs.safeScale));
    // Mode repos des yeux : réchauffe + abaisse la luminance.
    root.style.setProperty("--warmth", prefs.eyeRest ? "1" : "0");
    root.style.setProperty("--brightness", prefs.eyeRest ? "0.82" : "1");
    root.setAttribute("data-high-contrast", String(prefs.highContrast));
    root.setAttribute("data-reduced-motion", String(prefs.reducedMotion));
    root.setAttribute("data-vip", String(prefs.vip));
    root.setAttribute("data-eye-rest", String(prefs.eyeRest));
    root.setAttribute("data-ambilight", String(prefs.ambilight));
    root.setAttribute("data-parallax", String(prefs.parallax));
    root.setAttribute("data-profile", prefs.profile ?? "none");

    narration.setEnabled(prefs.narration);
    sound.setEnabled(prefs.soundCues);

    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
    } catch {
      /* quota / mode privé → on ignore */
    }
  }, [prefs, ready]);

  const setProfile = useCallback((p: ProfileId) => {
    setPrefs((prev) => ({ ...prev, profile: p, ...PROFILE_DEFAULTS[p] }));
  }, []);

  const update = useCallback((patch: Partial<Preferences>) => {
    setPrefs((prev) => ({ ...prev, ...patch }));
  }, []);

  const reset = useCallback(() => setPrefs(DEFAULTS), []);

  const value = useMemo<PreferencesContextValue>(
    () => ({ prefs, ready, setProfile, update, reset }),
    [prefs, ready, setProfile, update, reset],
  );

  return (
    <PreferencesContext.Provider value={value}>
      {children}
    </PreferencesContext.Provider>
  );
}

/// Hook d'accès aux préférences. Lance si utilisé hors provider (bug dev).
export function usePreferences(): PreferencesContextValue {
  const ctx = useContext(PreferencesContext);
  if (!ctx) {
    throw new Error("usePreferences doit être utilisé dans PreferencesProvider");
  }
  return ctx;
}
