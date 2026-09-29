import { describe, expect, it } from "vitest";
import { APP_DOWNLOADS, SHORT_LINKS } from "../app/lib/app-downloads";

// Les liens doivent rester ceux des releases publiées par la CI : une faute
// ici enverrait les clients vers une page 404.
describe("liens de téléchargement Zuno", () => {
  it("pointent vers les releases GitHub en https", () => {
    for (const url of Object.values(APP_DOWNLOADS)) {
      expect(url).toMatch(/^https:\/\/github\.com\/manzilionellm-dotcom\/tvking\/releases\/download\//);
    }
  });

  it("utilisent les noms de fichiers publiés par la CI", () => {
    expect(APP_DOWNLOADS.tvApk.endsWith("/zuno-tv/zuno-tv.apk")).toBe(true);
    expect(APP_DOWNLOADS.pcSetup.endsWith("/zuno-windows/Zuno-Setup.exe")).toBe(true);
    expect(APP_DOWNLOADS.pcZip.endsWith("/zuno-windows/zuno-windows.zip")).toBe(true);
  });

  it("raccourcis /apk et /pc", () => {
    expect(SHORT_LINKS["/apk"]).toBe(APP_DOWNLOADS.tvApk);
    expect(SHORT_LINKS["/pc"]).toBe(APP_DOWNLOADS.pcSetup);
    // Box de test : jamais la release lue par les box des clients.
    expect(SHORT_LINKS["/test"]).toBe(APP_DOWNLOADS.tvApkTest);
    expect(APP_DOWNLOADS.tvApkTest).toContain("/zuno-tv-test/");
  });
});
