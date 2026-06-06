"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import {
  COOKIE_PLAYLIST,
  COOKIE_EPG,
  xtreamToM3U,
  xtreamToEpg,
} from "../lib/config";
import { invalidateSource } from "../lib/source";

/*
 * Persist the user's source choice in cookies (per device) — the equivalent of
 * TiViMate's "Add playlist" step. Accepts either a direct M3U/XMLTV URL pair or
 * Xtream credentials, which we convert to the equivalent get.php / xmltv.php URL.
 */
const YEAR = 60 * 60 * 24 * 365;

export async function saveSource(formData: FormData): Promise<void> {
  const mode = String(formData.get("mode") || "m3u");
  const store = await cookies();

  let playlistUrl = "";
  let epgUrl = "";

  if (mode === "xtream") {
    const server = String(formData.get("server") || "").trim();
    const user = String(formData.get("username") || "").trim();
    const pass = String(formData.get("password") || "").trim();
    if (server && user && pass) {
      playlistUrl = xtreamToM3U(server, user, pass);
      epgUrl = xtreamToEpg(server, user, pass);
    }
  } else {
    playlistUrl = String(formData.get("playlistUrl") || "").trim();
    epgUrl = String(formData.get("epgUrl") || "").trim();
  }

  if (playlistUrl) {
    store.set(COOKIE_PLAYLIST, playlistUrl, { maxAge: YEAR, sameSite: "lax", path: "/" });
  }
  store.set(COOKIE_EPG, epgUrl, { maxAge: YEAR, sameSite: "lax", path: "/" });

  invalidateSource();
  revalidatePath("/", "layout");
}

/** Clear the configured source and fall back to env / public default. */
export async function resetSource(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE_PLAYLIST);
  store.delete(COOKIE_EPG);
  invalidateSource();
  revalidatePath("/", "layout");
}
