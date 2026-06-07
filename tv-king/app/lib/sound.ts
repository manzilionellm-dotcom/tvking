// =========================================================
//  sound.ts — Retours sonores doux (WebAudio, sans fichier binaire)
// =========================================================
//  Petits sons générés à la volée (pas d'asset audio). Désactivés par
//  défaut, activés via Réglages (utile en basse vision / pour le côté
//  premium VIP). Toujours discrets et brefs.
//
//  Comme la narration, on garde un contrôleur module-level pour rester
//  réactif depuis les handlers d'évènements, sans re-render.
// =========================================================

type Cue = "move" | "select" | "open";

class SoundController {
  private enabled = false;
  private ctx: AudioContext | null = null;

  setEnabled(on: boolean): void {
    this.enabled = on;
  }

  private ensureCtx(): AudioContext | null {
    if (typeof window === "undefined") return null;
    if (!this.ctx) {
      const Ctor =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext?: typeof AudioContext })
          .webkitAudioContext;
      if (!Ctor) return null;
      try {
        this.ctx = new Ctor();
      } catch {
        return null;
      }
    }
    return this.ctx;
  }

  /// Joue un petit « bip » sinusoïdal très court avec une enveloppe douce
  /// (attaque/déclin rapides) pour rester agréable et non agressif.
  play(cue: Cue): void {
    if (!this.enabled) return;
    const ctx = this.ensureCtx();
    if (!ctx) return;
    // Fréquences chaudes (or/ambre sonore) ; « open » plus riche.
    const freq = cue === "move" ? 420 : cue === "select" ? 540 : 660;
    const dur = cue === "move" ? 0.05 : 0.12;
    try {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = freq;
      const now = ctx.currentTime;
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.06, now + 0.01); // volume doux
      gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now);
      osc.stop(now + dur + 0.02);
    } catch {
      /* environnement audio indisponible → silencieux */
    }
  }
}

export const sound = new SoundController();
