/**
 * Device id (M2) — same format as admin-panel Activate + Flutter DeviceIdentity:
 *   MK:XX:XX:XX:XX:XX  (prefix MK + 5 octets)
 */

const PANEL_M2_RX = /^MK(?::[0-9A-F]{2}){5}$/i;
const CLASSIC_MAC_RX = /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/;

function hexOnly(s: string): string {
  return s.replace(/[^0-9A-Fa-f]/g, "").toUpperCase();
}

function formatPairs(hex: string, prefix?: string): string {
  const pairs = hex.match(/.{2}/g);
  if (!pairs) return "";
  const body = pairs.join(":");
  return prefix ? `${prefix}:${body}` : body;
}

/**
 * Normalize raw M2 / device id to panel form MK:XX:XX:XX:XX:XX when possible.
 * Also accepts 5 octets without MK, or classic 6-octet MAC (returned without MK).
 */
export function normalizeM2(input: string): string {
  const raw = (input || "").trim().toUpperCase();
  if (!raw) return "";

  if (PANEL_M2_RX.test(raw)) {
    const hex = hexOnly(raw.replace(/^MK/, ""));
    if (hex.length === 10) return formatPairs(hex, "MK");
  }

  const hasMk = /^MK[\s:\-]?/.test(raw);
  const hex = hexOnly(hasMk ? raw.replace(/^MK/, "") : raw);

  if (hex.length === 10) return formatPairs(hex, "MK");
  if (hex.length === 12) return formatPairs(hex);
  return "";
}

/** True when input is a valid panel M2 (MK + 5 octets) or classic 6-octet MAC. */
export function isValidM2(input: string): boolean {
  const n = normalizeM2(input);
  if (!n) return false;
  return PANEL_M2_RX.test(n) || CLASSIC_MAC_RX.test(n);
}

/** mac field for POST /api/v1/activate — panel requires MK:XX:XX:XX:XX:XX. */
export function toPanelMac(input: string): string | null {
  const n = normalizeM2(input);
  if (PANEL_M2_RX.test(n)) return n;
  return null;
}

/** @deprecated use normalizeM2 */
export function normalizeMac(input: string): string {
  return normalizeM2(input);
}

/** @deprecated use isValidM2 */
export function isValidMac(input: string): boolean {
  return isValidM2(input);
}
