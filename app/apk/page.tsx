import { redirect } from "next/navigation";
import { zunoAndroidDownloadUrl } from "../lib/downloads-public";

/** Convenience URL used on box browsers: zuno.7themotion.com/apk → official Zuno Android build */
export default function ApkRedirect() {
  redirect(zunoAndroidDownloadUrl());
}
