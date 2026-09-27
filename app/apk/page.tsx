import { redirect } from "next/navigation";

/** Convenience URL used on box browsers: zuno.7themotion.com/apk */
export default function ApkRedirect() {
  redirect(
    "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/zuno-tv.apk",
  );
}
