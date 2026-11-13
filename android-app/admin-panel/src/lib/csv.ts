// =========================================================
//  csv.ts — Exporter un tableau du panel vers Excel
// =========================================================
//  Fichier CSV lisible par Excel en français : séparateur « ; » et
//  marque UTF-8 en tête (sans elle, Excel abîme les accents).
//
//  SÉCURITÉ : une cellule qui commence par = + - @ serait exécutée
//  comme une formule par Excel. Un nom de client saisi à la main peut
//  en contenir : on la neutralise avec une apostrophe.
// =========================================================

export function csvCell(value: unknown): string {
  let s = value == null ? '' : String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[";\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

export function toCsv(headers: string[], rows: unknown[][]): string {
  const lines = [headers, ...rows].map((r) => r.map(csvCell).join(';'));
  return `﻿${lines.join('\r\n')}\r\n`;
}

/// Lance le téléchargement dans le navigateur. Rien n'est envoyé ailleurs.
export function downloadCsv(filename: string, headers: string[], rows: unknown[][]): void {
  const blob = new Blob([toCsv(headers, rows)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
