import { redirect } from "next/navigation";
import { DEFAULT_ZUNO_ANDROID_DOWNLOAD } from "../lib/downloads-public";

/** Stable Downloader URL on zuno.7themotion.com/apk → official signed APK release */
export default function ApkRedirect() {
  redirect(DEFAULT_ZUNO_ANDROID_DOWNLOAD);
}
