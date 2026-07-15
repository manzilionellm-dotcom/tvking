// =========================================================
//  metrics.js — Compteurs / jauges + rendu Prometheus
// =========================================================
//  Volontairement sans dépendance : un petit registre maison suffit et
//  reste lisible. Exposé en texte Prometheus sur /metrics.
// =========================================================

const counters = new Map();
const gauges = new Map();

function key(name, labels) {
  if (!labels) return name;
  const parts = Object.keys(labels)
    .sort()
    .map((k) => `${k}="${String(labels[k]).replace(/"/g, '')}"`);
  return `${name}{${parts.join(',')}}`;
}

export const metrics = {
  inc(name, by = 1, labels) {
    const k = key(name, labels);
    counters.set(k, (counters.get(k) || 0) + by);
  },
  setGauge(name, value, labels) {
    gauges.set(key(name, labels), value);
  },
  addGauge(name, by, labels) {
    const k = key(name, labels);
    gauges.set(k, (gauges.get(k) || 0) + by);
  },
  // Rendu texte compatible Prometheus.
  render() {
    const lines = [];
    for (const [k, v] of counters) lines.push(`${k} ${v}`);
    for (const [k, v] of gauges) lines.push(`${k} ${v}`);
    return lines.join('\n') + '\n';
  },
  // Instantané JSON (pour /admin/status).
  snapshot() {
    return {
      counters: Object.fromEntries(counters),
      gauges: Object.fromEntries(gauges),
    };
  },
};
