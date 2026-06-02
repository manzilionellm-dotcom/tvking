// =========================================================
//  narration.ts — Narration vocale (Web Speech API)
// =========================================================
//  Lit à voix haute le libellé de l'élément en focus et confirme les
//  actions. Indispensable pour les profils Senior / basse vision : la
//  qualité « premium » se ressent même sans bien voir l'écran.
//
//  Conçu défensif : si l'API n'existe pas (vieux navigateur, TV exotique)
//  tout est un no-op silencieux — jamais de crash.
//
//  On garde un petit contrôleur module-level (et non un état React) parce
//  que la narration est déclenchée depuis des handlers d'événements
//  (focus, activation) qui doivent rester ultra-réactifs et sans re-render.
// =========================================================

class NarrationController {
  private enabled = false;
  private lastText = "";
  private lastAt = 0;

  /// Activé/désactivé par le PreferencesProvider selon le réglage user.
  setEnabled(on: boolean): void {
    this.enabled = on;
    if (!on) this.cancel();
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  private get synth(): SpeechSynthesis | null {
    if (typeof window === "undefined") return null;
    return window.speechSynthesis ?? null;
  }

  /// Annonce un libellé (élément en focus). Anti-rebond : on ignore la
  /// répétition immédiate du même texte (le focus peut « rebondir »).
  speak(text: string): void {
    if (!this.enabled || !text) return;
    const synth = this.synth;
    if (!synth) return;

    const now = Date.now();
    if (text === this.lastText && now - this.lastAt < 500) return;
    this.lastText = text;
    this.lastAt = now;

    // On coupe l'annonce précédente : on ne veut pas empiler les phrases
    // quand l'utilisateur déplace vite le focus.
    synth.cancel();

    const u = new SpeechSynthesisUtterance(text);
    u.lang = "fr-FR";
    u.rate = 0.98; // voix posée, calme (édition VIP / Senior)
    u.pitch = 1;
    u.volume = 1;
    try {
      synth.speak(u);
    } catch {
      /* environnement sans synthèse vocale → silencieux */
    }
  }

  /// Confirme une action (« Ouverture de … »). Toujours coupe le reste.
  confirm(text: string): void {
    if (!this.enabled || !text) return;
    this.lastText = "";
    this.speak(text);
  }

  cancel(): void {
    this.synth?.cancel();
  }
}

/// Singleton partagé par toute l'app.
export const narration = new NarrationController();
