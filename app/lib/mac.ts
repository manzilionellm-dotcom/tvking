/** Normalize and validate MAC (AA:BB:CC:DD:EE:FF or similar). */
export function normalizeMac(input: string): string {
  const hex = input.replace(/[^0-9A-Fa-f]/g, "").toUpperCase();
  if (hex.length !== 12) return "";
  return hex.match(/.{2}/g)!.join(":");
}

export function isValidMac(input: string): boolean {
  return normalizeMac(input).length === 17;
}
