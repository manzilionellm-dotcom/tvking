"use client";

import {
  createContext,
  forwardRef,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { pushBackHandler } from "../lib/back";

/*
 * Clavier à l'écran INTÉGRÉ, piloté entièrement à la télécommande (D-pad +
 * OK). Il remplace le clavier système d'Android TV (« use the keyboard on your
 * mobile device ») : on n'a plus besoin du téléphone. Les champs texte de
 * l'app sont en lecture seule (`readOnly`) pour que le clavier système ne
 * s'ouvre JAMAIS ; à la place, sélectionner un champ ouvre ce clavier-ci.
 *
 * - Chaque touche est [data-focusable] -> SpatialNav la rend atteignable.
 * - OK valide, Annuler/BACK ferme sans changer la valeur.
 * - La fenêtre porte [data-focus-trap] : la navigation reste DANS le clavier.
 */

type KeyboardType = "text" | "password";

type OpenOpts = {
  title: string;
  value: string;
  type?: KeyboardType;
  onCommit: (value: string) => void;
};

type KeyboardApi = { open: (opts: OpenOpts) => void };

const Ctx = createContext<KeyboardApi | null>(null);

/** Hook d'accès : `useKeyboard().open({ title, value, type, onCommit })`. */
export function useKeyboard(): KeyboardApi {
  const api = useContext(Ctx);
  if (!api) throw new Error("useKeyboard must be used within <KeyboardProvider>");
  return api;
}

// Dispositions de touches. Pensées pour les URL/identifiants IPTV (lettres,
// chiffres, et symboles utiles : . : / @ - _). AZERTY pour le public FR.
const LETTERS = [
  ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
  ["w", "x", "c", "v", "b", "n"],
];
const DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
const SYMBOLS = [
  [".", ":", "/", "@", "-", "_", "+", "=", "?", "&"],
  ["%", "#", "(", ")", "!", ",", ";", "*", "~", "$"],
  ["'", '"', "<", ">", "[", "]", "{", "}", "\\", "|"],
];

export function KeyboardProvider({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [opts, setOpts] = useState<OpenOpts | null>(null);
  const [text, setText] = useState("");
  const [shift, setShift] = useState(false);
  const [symbols, setSymbols] = useState(false);
  const [reveal, setReveal] = useState(false);
  const firstKeyRef = useRef<HTMLButtonElement>(null);
  // Élément (champ) qui avait le focus à l'ouverture : on le restaure à la
  // fermeture pour que la télécommande reprenne là où on était.
  const openerRef = useRef<HTMLElement | null>(null);

  const api: KeyboardApi = {
    open: useCallback((o: OpenOpts) => {
      openerRef.current = document.activeElement as HTMLElement | null;
      setOpts(o);
      setText(o.value ?? "");
      setShift(false);
      setSymbols(false);
      setReveal(false);
      setOpen(true);
    }, []),
  };

  const close = useCallback(() => {
    setOpen(false);
    setOpts(null);
    const opener = openerRef.current;
    if (opener) window.setTimeout(() => opener.focus(), 0);
  }, []);

  const commit = useCallback(() => {
    opts?.onCommit(text);
    close();
  }, [opts, text, close]);

  // BACK ferme le clavier (sans valider) tant qu'il est ouvert.
  useEffect(() => {
    if (!open) return;
    const off = pushBackHandler(() => {
      close();
      return true;
    });
    // Donne le focus à la première touche pour un départ télécommande net.
    const id = window.setTimeout(() => firstKeyRef.current?.focus(), 30);
    return () => {
      off();
      window.clearTimeout(id);
    };
  }, [open, close]);

  const isPassword = opts?.type === "password";
  const display = isPassword && !reveal ? "•".repeat(text.length) : text;

  const press = (ch: string) => {
    setText((t) => t + (shift ? ch.toUpperCase() : ch));
    if (shift) setShift(false); // Maj = une seule lettre (comme un smartphone).
  };

  return (
    <Ctx.Provider value={api}>
      {children}
      {open && opts && (
        <div
          data-focus-trap
          className="fixed inset-0 z-[100] flex flex-col items-center justify-end"
          style={{ background: "var(--scrim)" }}
        >
          <div className="w-full max-w-[60rem] rounded-t-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.6rem] shadow-[0_-1rem_4rem_rgba(0,0,0,0.6)]">
            {/* Titre + aperçu de la saisie */}
            <div className="mb-[1.2rem] flex items-center gap-[1rem]">
              <span className="text-[1.15rem] font-semibold text-[var(--text-medium)]">
                {opts.title}
              </span>
              <div className="flex min-h-[2.8rem] flex-1 items-center rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] text-[1.4rem] text-[var(--text-high)]">
                <span className="break-all">{display}</span>
                <span className="ml-[0.1rem] inline-block h-[1.5rem] w-[0.12rem] animate-pulse bg-[var(--accent)]" />
              </div>
              {isPassword && (
                <Key onPress={() => setReveal((r) => !r)} wide>
                  {reveal ? "Cacher" : "Afficher"}
                </Key>
              )}
            </div>

            {/* Chiffres (toujours visibles, pratique pour ports/URL) */}
            <Row>
              {DIGITS.map((d) => (
                <Key key={d} onPress={() => setText((t) => t + d)}>
                  {d}
                </Key>
              ))}
            </Row>

            {/* Lettres OU symboles */}
            {(symbols ? SYMBOLS : LETTERS).map((row, ri) => (
              <Row key={ri}>
                {row.map((ch, ci) => (
                  <Key
                    key={ch}
                    ref={ri === 0 && ci === 0 ? firstKeyRef : undefined}
                    onPress={() => (symbols ? setText((t) => t + ch) : press(ch))}
                  >
                    {!symbols && shift ? ch.toUpperCase() : ch}
                  </Key>
                ))}
              </Row>
            ))}

            {/* Touches d'action */}
            <Row>
              {!symbols && (
                <Key onPress={() => setShift((s) => !s)} wide active={shift}>
                  ⇧ Maj
                </Key>
              )}
              <Key onPress={() => setSymbols((s) => !s)} wide active={symbols}>
                {symbols ? "ABC" : "?123"}
              </Key>
              <Key onPress={() => setText((t) => t + " ")} grow>
                Espace
              </Key>
              <Key onPress={() => setText((t) => t.slice(0, -1))} wide>
                ⌫
              </Key>
              <Key onPress={() => setText("")} wide>
                Effacer
              </Key>
            </Row>

            <Row>
              <Key onPress={close} grow>
                Annuler
              </Key>
              <Key onPress={commit} grow primary>
                OK
              </Key>
            </Row>
          </div>
        </div>
      )}
    </Ctx.Provider>
  );
}

function Row({ children }: { children: React.ReactNode }) {
  return <div className="mb-[0.6rem] flex justify-center gap-[0.5rem]">{children}</div>;
}

type KeyProps = {
  children: React.ReactNode;
  onPress: () => void;
  wide?: boolean;
  grow?: boolean;
  primary?: boolean;
  active?: boolean;
};

const Key = forwardRef<HTMLButtonElement, KeyProps>(function Key(
  { children, onPress, wide, grow, primary, active },
  ref,
) {
  return (
    <button
      ref={ref}
      data-focusable
      onClick={onPress}
      className={`focusable flex h-[3.4rem] items-center justify-center rounded-[var(--radius)] px-[0.9rem] text-[1.25rem] font-semibold ${
        grow ? "flex-1" : wide ? "min-w-[6rem] px-[1.2rem]" : "min-w-[3.4rem]"
      }`}
      style={
        primary
          ? { background: "var(--accent-grad)", color: "#000" }
          : {
              background: active ? "var(--accent)" : "var(--surface-3)",
              color: active ? "#000" : "var(--text-high)",
            }
      }
    >
      {children}
    </button>
  );
});
