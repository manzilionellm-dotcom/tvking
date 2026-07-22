// =========================================================
//  ratelimit.js — Limiteur de débit à fenêtre glissante (pur)
// =========================================================
//  Sans dépendance ni timer : on garde, par clé, les horodatages des
//  requêtes récentes et on compte celles encore dans la fenêtre. L'horloge
//  est injectable (tests déterministes).
// =========================================================

export class RateLimiter {
  /**
   * @param {number} max      Requêtes autorisées par fenêtre (0 = désactivé).
   * @param {number} windowMs Largeur de la fenêtre en ms.
   * @param {() => number} now Source d'horloge (ms). Injectable pour les tests.
   */
  constructor(max, windowMs, now = () => Date.now()) {
    this.max = max;
    this.windowMs = windowMs;
    this._now = now;
    this._hits = new Map(); // clé -> number[] (horodatages triés croissants)
  }

  /** true si la requête est autorisée (et la comptabilise), false sinon. */
  allow(key) {
    if (this.max <= 0) return true; // désactivé
    const t = this._now();
    const cutoff = t - this.windowMs;
    const arr = this._hits.get(key) || [];
    // Purge des horodatages sortis de la fenêtre (arr trié → on coupe la tête).
    let i = 0;
    while (i < arr.length && arr[i] <= cutoff) i++;
    const recent = i > 0 ? arr.slice(i) : arr;
    if (recent.length >= this.max) {
      this._hits.set(key, recent);
      return false;
    }
    recent.push(t);
    this._hits.set(key, recent);
    return true;
  }
}
