#!/usr/bin/env node
/*
 * size-budget.mjs — client-JS size budget (Loi 10: livrer seulement si les
 * budgets ≥ baseline). Sums the built client JavaScript in `.next/static` and
 * compares it to a committed baseline.
 *
 *   node scripts/size-budget.mjs          # check against baseline (CI gate)
 *   node scripts/size-budget.mjs --write  # (re)write the baseline
 *
 * Honest by construction: with no baseline yet, the first run WRITES it and
 * passes — nothing is a "regression" until there is a reference. Afterwards a
 * growth beyond MARGIN fails the build.
 */
import { readdirSync, statSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";

const STATIC_DIR = ".next/static";
const BASELINE = ".company/data/perf/baseline.json";
const MARGIN = 0.1; // allow +10% before failing

function sumJs(dir) {
  let total = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) total += sumJs(p);
    else if (entry.name.endsWith(".js")) total += statSync(p).size;
  }
  return total;
}

if (!existsSync(STATIC_DIR)) {
  console.error(`✗ ${STATIC_DIR} introuvable — lance \`npm run build\` d'abord.`);
  process.exit(2);
}

const bytes = sumJs(STATIC_DIR);
const kb = (n) => `${(n / 1024).toFixed(1)} KiB`;
const write = process.argv.includes("--write");

if (write || !existsSync(BASELINE)) {
  mkdirSync(dirname(BASELINE), { recursive: true });
  const prev = existsSync(BASELINE) ? JSON.parse(readFileSync(BASELINE, "utf8")) : null;
  writeFileSync(
    BASELINE,
    JSON.stringify({ staticJsBytes: bytes, unit: "bytes", metric: "sum(.next/static/**/*.js)" }, null, 2) + "\n",
  );
  console.log(`✓ Baseline écrite : ${kb(bytes)}${prev ? ` (ancien ${kb(prev.staticJsBytes)})` : ""}`);
  process.exit(0);
}

const base = JSON.parse(readFileSync(BASELINE, "utf8")).staticJsBytes;
const limit = Math.round(base * (1 + MARGIN));
const delta = ((bytes - base) / base) * 100;
const sign = delta >= 0 ? "+" : "";
console.log(`Client JS : ${kb(bytes)} | baseline ${kb(base)} | budget ${kb(limit)} | ${sign}${delta.toFixed(1)}%`);

if (bytes > limit) {
  console.error(`✗ Budget de taille dépassé (> +${MARGIN * 100}%). REJETÉ → backlog.`);
  process.exit(1);
}
console.log("✓ Budget de taille respecté.");
