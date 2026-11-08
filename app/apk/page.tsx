import { redirect } from "next/navigation";

/** Latest available ZUNO TV signed APK (test channel, pending production validation). */
const LATEST_ZUNO_TV_APK =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk";

/** Stable Downloader URL on zuno.7themotion.com/apk. */
export default function ApkRedirect() {
  redirect(LATEST_ZUNO_TV_APK);
}
