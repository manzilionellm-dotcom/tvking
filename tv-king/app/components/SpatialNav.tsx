"use client";

// =========================================================
//  SpatialNav.tsx — Navigation spatiale à la télécommande
// =========================================================
//  Principe « personne n'est perdu » : UN SEUL élément a le focus, on ne
//  peut jamais le perdre, et la touche RETOUR est prévisible partout.
//
//  Tout se fait avec 5 touches : ↑ ↓ ← → + OK (Entrée/Espace), plus
//  RETOUR (Échap / Retour arrière).
//
//  Algorithme (modèle Android TV « élément le plus proche ») : depuis le
//  centre de l'élément courant, on cherche le meilleur candidat DANS la
//  direction pressée. Score = distance le long de l'axe + distance
//  hors-axe × 2.5 (on pénalise le décalage latéral pour rester aligné).
//
//  Mémoire de focus par page : en revenant sur une page, on restaure le
//  dernier élément qui avait le focus (sinon on focalise le premier).
// =========================================================

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useRef } from "react";
import { narration } from "../lib/narration";

type Dir = "up" | "down" | "left" | "right";

/// Mémoire (module-level) du dernier élément focalisé par chemin d'URL.
/// On stocke un identifiant stable (`data-nav-id` ou `id`) pour le
/// retrouver après un changement de page.
const focusMemory = new Map<string, string>();

function isFormField(el: Element | null): boolean {
  if (!el) return false;
  const tag = el.tagName.toLowerCase();
  return tag === "input" || tag === "textarea" || tag === "select";
}

function visibleFocusables(): HTMLElement[] {
  const all = Array.from(
    document.querySelectorAll<HTMLElement>("[data-focusable]"),
  );
  // On ignore les éléments masqués (display:none → pas de rects).
  return all.filter((el) => el.offsetParent !== null || el === document.activeElement);
}

function navId(el: HTMLElement): string | null {
  return el.getAttribute("data-nav-id") ?? (el.id || null);
}

function labelOf(el: HTMLElement): string {
  return (
    el.getAttribute("aria-label") ??
    el.getAttribute("data-label") ??
    el.textContent?.trim() ??
    ""
  );
}

export function SpatialNav() {
  const router = useRouter();
  const pathname = usePathname();
  const currentRef = useRef<HTMLElement | null>(null);

  /// Applique le focus à un élément : marque visuel + focus DOM + scroll
  /// centré + narration. C'est le SEUL endroit qui change le focus.
  const setFocus = useCallback(
    (el: HTMLElement | null, opts?: { scroll?: boolean }) => {
      if (!el) return;
      if (currentRef.current && currentRef.current !== el) {
        currentRef.current.removeAttribute("data-focused");
      }
      el.setAttribute("data-focused", "true");
      currentRef.current = el;

      try {
        el.focus({ preventScroll: true });
      } catch {
        /* certains éléments non focusables nativement → on garde le visuel */
      }

      if (opts?.scroll !== false) {
        const reduced =
          document.documentElement.getAttribute("data-reduced-motion") ===
          "true";
        el.scrollIntoView({
          behavior: reduced ? "auto" : "smooth",
          block: "center",
          inline: "center",
        });
      }

      // Mémorise pour le retour sur cette page.
      const id = navId(el);
      if (id) focusMemory.set(pathname, id);

      narration.speak(labelOf(el));
    },
    [pathname],
  );

  /// Cherche le meilleur candidat dans une direction depuis l'élément
  /// courant et l'y focalise. Retourne true si un candidat a été trouvé.
  const move = useCallback(
    (dir: Dir): boolean => {
      const items = visibleFocusables();
      const cur = currentRef.current;
      if (!cur || items.length === 0) {
        if (items[0]) setFocus(items[0]);
        return Boolean(items[0]);
      }
      const c = cur.getBoundingClientRect();
      const cx = c.left + c.width / 2;
      const cy = c.top + c.height / 2;

      let best: HTMLElement | null = null;
      let bestScore = Number.POSITIVE_INFINITY;

      for (const el of items) {
        if (el === cur) continue;
        const r = el.getBoundingClientRect();
        const x = r.left + r.width / 2;
        const y = r.top + r.height / 2;
        const dx = x - cx;
        const dy = y - cy;

        let along: number;
        let off: number;
        const margin = 8; // tolérance pour ignorer le bruit d'alignement
        switch (dir) {
          case "left":
            if (dx >= -margin) continue;
            along = -dx;
            off = Math.abs(dy);
            break;
          case "right":
            if (dx <= margin) continue;
            along = dx;
            off = Math.abs(dy);
            break;
          case "up":
            if (dy >= -margin) continue;
            along = -dy;
            off = Math.abs(dx);
            break;
          case "down":
            if (dy <= margin) continue;
            along = dy;
            off = Math.abs(dx);
            break;
        }
        // Pénalise fortement le décalage hors-axe (×2.5) pour garder un
        // déplacement « droit » et prévisible.
        const sc = along + off * 2.5;
        if (sc < bestScore) {
          bestScore = sc;
          best = el;
        }
      }

      if (best) {
        setFocus(best);
        return true;
      }
      return false;
    },
    [setFocus],
  );

  // ----- Gestion clavier (télécommande) -----
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const active = document.activeElement;

      switch (e.key) {
        case "ArrowUp":
          if (isFormField(active)) return;
          e.preventDefault();
          move("up");
          break;
        case "ArrowDown":
          if (isFormField(active)) return;
          e.preventDefault();
          move("down");
          break;
        case "ArrowLeft":
          if (isFormField(active)) return;
          e.preventDefault();
          move("left");
          break;
        case "ArrowRight":
          if (isFormField(active)) return;
          e.preventDefault();
          move("right");
          break;
        case "Enter":
        case " ": // Espace = OK
          // Dans un champ texte, Entrée a son sens propre (submit) → on
          // laisse passer. Sinon OK = activer l'élément focalisé.
          if (isFormField(active)) return;
          e.preventDefault();
          currentRef.current?.click();
          break;
        case "Backspace":
        case "Escape":
          // RETOUR prévisible : on revient à la page précédente. Jamais
          // d'action destructrice. Dans un champ, Backspace efface.
          if (e.key === "Backspace" && isFormField(active)) return;
          e.preventDefault();
          router.back();
          break;
        default:
          break;
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [move, router]);

  // ----- Souris : un clic/focus synchronise l'état courant -----
  useEffect(() => {
    function onFocusIn(e: FocusEvent) {
      const t = e.target as HTMLElement | null;
      if (t && t.hasAttribute("data-focusable") && t !== currentRef.current) {
        if (currentRef.current) currentRef.current.removeAttribute("data-focused");
        t.setAttribute("data-focused", "true");
        currentRef.current = t;
        const id = navId(t);
        if (id) focusMemory.set(pathname, id);
      }
    }
    document.addEventListener("focusin", onFocusIn);
    return () => document.removeEventListener("focusin", onFocusIn);
  }, [pathname]);

  // ----- Focus initial / restauration à chaque changement de page -----
  useEffect(() => {
    // On laisse le DOM se peindre (rAF) avant de chercher les focusables.
    const raf = requestAnimationFrame(() => {
      currentRef.current = null;
      const items = visibleFocusables();
      if (items.length === 0) return;

      const remembered = focusMemory.get(pathname);
      const target =
        (remembered &&
          items.find((el) => navId(el) === remembered)) ||
        items[0];
      // Pas de scroll « smooth » à l'arrivée (évite un défilement brutal).
      setFocus(target, { scroll: true });
    });
    return () => cancelAnimationFrame(raf);
  }, [pathname, setFocus]);

  // Composant purement comportemental : aucun rendu visuel.
  return null;
}
