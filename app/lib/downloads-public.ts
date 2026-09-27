/** Official Zuno Android download (AAB). Override via env when Lionel rotates the asset. */
export const DEFAULT_ZUNO_ANDROID_DOWNLOAD =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/zuno-tv.aab";

/** Package / applicationId note for sideload help text. */
export const ZUNO_ANDROID_PACKAGE_ID = "com.sevenmotion.tv.seven_tv";

export function zunoAndroidDownloadUrl(): string {
  const fromEnv =
    process.env.NEXT_PUBLIC_ZUNO_DOWNLOAD_ANDROID ||
    process.env.NEXT_PUBLIC_ZUNO_DOWNLOAD_AAB ||
    process.env.NEXT_PUBLIC_ZUNO_DOWNLOAD_URL;
  if (fromEnv && fromEnv.trim() !== "" && fromEnv !== "#") return fromEnv.trim();
  return DEFAULT_ZUNO_ANDROID_DOWNLOAD;
}
