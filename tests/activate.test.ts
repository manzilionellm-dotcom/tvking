import { describe, expect, it } from "vitest";
import { normalizeM2, isValidM2, toPanelMac } from "../app/lib/mac";
import { planFromSCode, normalizePlanToken, panelActivateBody } from "../app/lib/activate";

describe("M2 / panel mac", () => {
  it("normalizes MK form", () => {
    expect(normalizeM2("mk:1a:2b:3c:4d:5e")).toBe("MK:1A:2B:3C:4D:5E");
    expect(normalizeM2("MK1A2B3C4D5E")).toBe("MK:1A:2B:3C:4D:5E");
    expect(normalizeM2("1A:2B:3C:4D:5E")).toBe("MK:1A:2B:3C:4D:5E");
    expect(toPanelMac("mk:aa:bb:cc:dd:ee")).toBe("MK:AA:BB:CC:DD:EE");
    expect(isValidM2("MK:AA:BB:CC:DD:EE")).toBe(true);
  });

  it("rejects garbage", () => {
    expect(normalizeM2("nope")).toBe("");
    expect(toPanelMac("AA:BB:CC:DD:EE:FF")).toBe(null); // 6-octet not panel M2
  });
});

describe("S code → plan", () => {
  it("maps lifetime / yearly tokens", () => {
    expect(normalizePlanToken("lifetime")).toBe("lifetime");
    expect(normalizePlanToken("vie")).toBe("lifetime");
    expect(normalizePlanToken("yearly")).toBe("yearly");
    expect(normalizePlanToken("annuel")).toBe("yearly");
    expect(planFromSCode("LIFETIME")).toBe("lifetime");
    expect(planFromSCode("YEARLY")).toBe("yearly");
    expect(planFromSCode("ZUNO-LIFE-99")).toBe("lifetime");
    expect(planFromSCode("ZUNO-YEAR-01")).toBe("yearly");
  });

  it("builds panel body", () => {
    expect(panelActivateBody("MK:AA:BB:CC:DD:EE", "yearly")).toEqual({
      mac: "MK:AA:BB:CC:DD:EE",
      plan: "yearly",
      app_id: "app_7motion",
    });
  });
});
