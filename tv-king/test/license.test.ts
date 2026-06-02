import { describe, expect, it } from "vitest";
import {
  gateReason,
  isOnTrial,
  MAC_REGEX,
  parseStatus,
  randomMac,
  shouldBlock,
  type LicenseStatus,
} from "../app/lib/license";

const base: LicenseStatus = {
  exists: true,
  status: "active",
  paid: false,
  daysLeft: 7,
  expired: false,
  frozen: false,
  banned: false,
  trialUntil: Date.now() + 7 * 86400000,
  reachable: true,
};

describe("MAC virtuel", () => {
  it("randomMac respecte le format MK:XX:XX:XX:XX:XX", () => {
    for (let i = 0; i < 50; i++) {
      expect(MAC_REGEX.test(randomMac())).toBe(true);
    }
  });

  it("deux MAC tirés sont (quasi toujours) différents", () => {
    expect(randomMac()).not.toBe(randomMac());
  });
});

describe("parseStatus (snake_case serveur → camelCase app)", () => {
  it("mappe correctement les champs", () => {
    const s = parseStatus(
      {
        exists: true,
        status: "active",
        paid: true,
        days_left: 365,
        expired: false,
        frozen: false,
        banned: false,
        trial_until: 123,
      },
      true,
    );
    expect(s.paid).toBe(true);
    expect(s.daysLeft).toBe(365);
    expect(s.trialUntil).toBe(123);
    expect(s.reachable).toBe(true);
  });

  it("json null → état injoignable", () => {
    expect(parseStatus(null, false).reachable).toBe(false);
  });
});

describe("logique de blocage", () => {
  it("essai en cours : pas de blocage", () => {
    expect(shouldBlock(base)).toBe(false);
    expect(gateReason(base)).toBeNull();
    expect(isOnTrial(base)).toBe(true);
  });

  it("essai expiré non payé : bloqué (trial-expired)", () => {
    const s = { ...base, expired: true, daysLeft: 0 };
    expect(shouldBlock(s)).toBe(true);
    expect(gateReason(s)).toBe("trial-expired");
    expect(isOnTrial(s)).toBe(false);
  });

  it("payé : jamais bloqué même si expired", () => {
    const s = { ...base, expired: true, paid: true };
    expect(shouldBlock(s)).toBe(false);
  });

  it("gelé et banni priment", () => {
    expect(gateReason({ ...base, frozen: true })).toBe("frozen");
    expect(gateReason({ ...base, banned: true })).toBe("banned");
  });

  it("hors-ligne : on ne bloque jamais (fail-open)", () => {
    const s = { ...base, expired: true, banned: true, reachable: false };
    expect(shouldBlock(s)).toBe(false);
  });
});
