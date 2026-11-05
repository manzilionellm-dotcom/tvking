import { redirect } from "next/navigation";
import { zunoAndroidDownloadUrl } from "../lib/downloads-public";

/** Stable Downloader URL on zuno.7themotion.com/apk → official signed APK release */
export default function ApkRedirect() {
  redirect(zunoAndroidDownloadUrl());
}
