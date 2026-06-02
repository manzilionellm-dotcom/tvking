"use client";

// =========================================================
//  VoiceButton.tsx — Recherche / commande vocale (Web Speech API)
// =========================================================
//  Bouton micro qui écoute une phrase et la renvoie au parent. Repli
//  GRACIEUX : si le réglage « voix » est off OU si l'API de
//  reconnaissance n'existe pas, le bouton ne s'affiche pas (la recherche
//  reste utilisable au clavier / aux chips). Aucune dépendance externe.
// =========================================================

import { useEffect, useRef, useState } from "react";
import { narration } from "../lib/narration";
import { usePreferences } from "../lib/preferences";

// Types minimaux de l'API (non typée par TS) — on évite `any`.
interface SpeechResultAlt {
  transcript: string;
}
interface SpeechResultList {
  length: number;
  [i: number]: { 0: SpeechResultAlt };
}
interface SpeechEventLike {
  results: SpeechResultList;
}
interface RecognitionLike {
  lang: string;
  interimResults: boolean;
  maxAlternatives: number;
  onresult: ((e: SpeechEventLike) => void) | null;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  start: () => void;
  stop: () => void;
}
type RecognitionCtor = new () => RecognitionLike;

function getRecognitionCtor(): RecognitionCtor | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: RecognitionCtor;
    webkitSpeechRecognition?: RecognitionCtor;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export function VoiceButton({ onText }: { onText: (text: string) => void }) {
  const { prefs } = usePreferences();
  const [supported, setSupported] = useState(false);
  const [listening, setListening] = useState(false);
  const recRef = useRef<RecognitionLike | null>(null);

  useEffect(() => {
    setSupported(getRecognitionCtor() !== null);
  }, []);

  if (!prefs.voice || !supported) return null;

  function listen() {
    const Ctor = getRecognitionCtor();
    if (!Ctor) return;
    const rec = new Ctor();
    recRef.current = rec;
    rec.lang = "fr-FR";
    rec.interimResults = false;
    rec.maxAlternatives = 1;
    rec.onresult = (e) => {
      const text = e.results?.[0]?.[0]?.transcript ?? "";
      if (text) onText(text);
    };
    rec.onend = () => setListening(false);
    rec.onerror = () => setListening(false);
    setListening(true);
    narration.confirm("Je vous écoute");
    try {
      rec.start();
    } catch {
      setListening(false);
    }
  }

  return (
    <button
      type="button"
      className="focusable"
      data-focusable
      data-nav-id="voice-btn"
      aria-label="Recherche vocale : appuyez puis parlez"
      onClick={listen}
      style={{
        cursor: "pointer",
        marginLeft: "0.8rem",
        width: "3.4rem",
        height: "3.4rem",
        borderRadius: "999px",
        border: "1px solid rgba(255,255,255,0.2)",
        background: listening ? "var(--gold-grad)" : "var(--surface-2)",
        color: listening ? "#1a1300" : "var(--text-high)",
        fontSize: "1.5rem",
      }}
    >
      🎤
    </button>
  );
}
