import { redirect } from "next/navigation";

/** Stable Windows download URL on zuno8k.com/windows → current ZUNO Windows installer */
const ZUNO_WINDOWS_DOWNLOAD =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/Zuno-Setup.exe";

export default function WindowsRedirect() {
  redirect(ZUNO_WINDOWS_DOWNLOAD);
}
