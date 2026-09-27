/*
 * Liens de téléchargement de l'application Zuno (source unique du site).
 *
 * Ces adresses sont STABLES : chaque nouvelle version publiée par la CI
 * (build-zuno-tv.yml, build-zuno-windows.yml) remplace le fichier au même
 * endroit. La page /telecharger et les raccourcis /apk et /pc donnent donc
 * toujours la dernière version, sans jamais modifier le site.
 */

const RELEASES = "https://github.com/manzilionellm-dotcom/tvking/releases/download";

export const APP_DOWNLOADS = {
  /** Box Android TV / Fire TV / Google TV (APK, installation par-dessus). */
  tvApk: `${RELEASES}/zuno-tv/zuno-tv.apk`,
  /** PC Windows 10/11 64 bits — installateur. */
  pcSetup: `${RELEASES}/zuno-windows/Zuno-Setup.exe`,
  /** PC Windows — version portable (dézipper, lancer tv_king.exe). */
  pcZip: `${RELEASES}/zuno-windows/zuno-windows.zip`,
} as const;

/** Raccourcis courts, faciles à taper sur une télécommande (app Downloader). */
export const SHORT_LINKS = {
  "/apk": APP_DOWNLOADS.tvApk,
  "/pc": APP_DOWNLOADS.pcSetup,
} as const;
