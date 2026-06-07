"use client";

import { useState } from "react";
import DisplaySettings from "../components/DisplaySettings";
import DeviceCard from "../components/DeviceCard";
import { useSource, setConfig, clearConfig } from "../lib/client-source";
import { useT } from "../lib/i18n";

/*
 * Réglages source + affichage. La source se configure UNIQUEMENT en Xtream
 * Codes (serveur / utilisateur / mot de passe) — convertis en get.php / xmltv.php.
 * Les flux sont demandés en HLS (`output=m3u8`) pour qu'ils jouent dans la
 * WebView de l'APK (le MPEG-TS brut n'y est pas décodé nativement). Le choix
 * est mémorisé par appareil (localStorage) et la source recharge aussitôt.
 */
function xtreamUrls(server: string, user: string, pass: string) {
  const base = server.replace(/\/+$/, "");
  const u = encodeURIComponent(user);
  const p = encodeURIComponent(pass);
  return {
    // output=m3u8 → URLs de chaînes en HLS (lisibles par hls.js dans la WebView).
    playlistUrl: `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=m3u8`,
    epgUrl: `${base}/xmltv.php?username=${u}&password=${p}`,
  };
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  type?: string;
}) {
  return (
    <label className="flex flex-col gap-[0.3rem]">
      <span className="text-[0.95rem] font-semibold text-[var(--text-medium)]">{label}</span>
      <input
        type={type}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        data-focusable
        className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.7rem] text-[1.1rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)]"
      />
    </label>
  );
}

export default function SettingsPage() {
  const { status, playlist, config, error } = useSource();
  const t = useT();

  const [server, setServer] = useState("");
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");

  const loading = status === "loading" || status === "idle";

  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[0.4rem] font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">
        {t("nav_settings")}
      </h1>
      <p className="mb-[1.6rem] text-[1.05rem] text-[var(--text-medium)]">{t("settings_subtitle")}</p>

      {/* Source status */}
      <div className="mb-[1.6rem] max-w-[52rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
        <div className="flex items-center gap-[0.7rem]">
          <span
            className="h-[0.8rem] w-[0.8rem] rounded-full"
            style={{ background: loading ? "var(--accent)" : playlist.total > 0 ? "var(--ok)" : "var(--live)" }}
          />
          <span className="text-[1.15rem] font-bold text-[var(--text-high)]">
            {loading
              ? t("loading")
              : playlist.total > 0
                ? t("channels_loaded", { n: playlist.total })
                : t("no_channel")}
          </span>
          {!loading && (
            <span className="text-[1rem] text-[var(--text-medium)]">
              · {playlist.groups.length} {t("categories")}
            </span>
          )}
        </div>
        {config.playlistUrl && (
          <p className="mt-[0.5rem] break-all text-[0.9rem] text-[var(--text-disabled)]">
            {t("server_connected")} : {config.playlistUrl.replace(/(password=)[^&]*/i, "$1•••")}
          </p>
        )}
        {error && <p className="mt-[0.5rem] text-[0.95rem] text-[var(--live)]">⚠ {error}</p>}
      </div>

      {/* Xtream Codes — seule méthode de connexion */}
      <div className="flex max-w-[52rem] flex-col gap-[0.8rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
        <h2 className="text-[1.3rem] font-bold text-[var(--text-high)]">Xtream Codes</h2>
        <p className="text-[0.95rem] text-[var(--text-medium)]">{t("xtream_help")}</p>
        <Field label={t("server")} value={server} onChange={setServer} placeholder="http://serveur:8080" />
        <Field label={t("username")} value={user} onChange={setUser} placeholder="utilisateur" />
        <Field label={t("password")} value={pass} onChange={setPass} type="password" placeholder="••••••••" />
        <button
          data-focusable
          onClick={() => {
            if (!server || !user || !pass) return;
            setConfig(xtreamUrls(server.trim(), user.trim(), pass.trim()));
          }}
          className="focusable mt-[0.4rem] rounded-[var(--radius)] px-[1.4rem] py-[0.8rem] text-[1.1rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          {t("connect")}
        </button>
      </div>

      {/* Activation à distance — code de l'appareil + état */}
      <DeviceCard />

      {/* Display */}
      <h2 className="mb-[0.8rem] mt-[2rem] text-[1.3rem] font-bold text-[var(--text-high)]">{t("display")}</h2>
      <DisplaySettings />

      <button
        data-focusable
        onClick={() => {
          clearConfig();
          setServer("");
          setUser("");
          setPass("");
        }}
        className="focusable mt-[2rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-medium)]"
      >
        {t("reset_source")}
      </button>
    </div>
  );
}
