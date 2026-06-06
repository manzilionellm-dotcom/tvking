import DisplaySettings from "../components/DisplaySettings";
import { loadSource } from "../lib/source";
import { saveSource, resetSource } from "./actions";

export const dynamic = "force-dynamic";

function Field({
  label,
  name,
  placeholder,
  defaultValue,
  type = "text",
}: {
  label: string;
  name: string;
  placeholder?: string;
  defaultValue?: string;
  type?: string;
}) {
  return (
    <label className="flex flex-col gap-[0.3rem]">
      <span className="text-[0.95rem] font-semibold text-[var(--text-medium)]">{label}</span>
      <input
        name={name}
        type={type}
        placeholder={placeholder}
        defaultValue={defaultValue}
        data-focusable
        className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.7rem] text-[1.1rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)]"
      />
    </label>
  );
}

export default async function SettingsPage() {
  const { playlist, config, error } = await loadSource();

  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[0.4rem] font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">
        Réglages
      </h1>
      <p className="mb-[1.6rem] text-[1.05rem] text-[var(--text-medium)]">
        Configurez votre source IPTV (M3U/Xtream + guide XMLTV) et l’affichage.
      </p>

      {/* Source status */}
      <div className="mb-[1.6rem] max-w-[52rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
        <div className="flex items-center gap-[0.7rem]">
          <span
            className="h-[0.8rem] w-[0.8rem] rounded-full"
            style={{ background: playlist.total > 0 ? "var(--ok)" : "var(--live)" }}
          />
          <span className="text-[1.15rem] font-bold text-[var(--text-high)]">
            {playlist.total > 0 ? `${playlist.total} chaînes chargées` : "Aucune chaîne"}
          </span>
          <span className="text-[1rem] text-[var(--text-medium)]">· {playlist.groups.length} catégories</span>
        </div>
        <p className="mt-[0.5rem] break-all text-[0.9rem] text-[var(--text-disabled)]">
          Playlist : {config.playlistUrl || "—"}
          <br />
          EPG : {config.epgUrl || "(aucun)"}
        </p>
        {error && <p className="mt-[0.5rem] text-[0.95rem] text-[var(--live)]">⚠ {error}</p>}
      </div>

      <div className="grid max-w-[80rem] gap-[1.4rem] lg:grid-cols-2">
        {/* M3U / XMLTV */}
        <form action={saveSource} className="flex flex-col gap-[0.8rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
          <input type="hidden" name="mode" value="m3u" />
          <h2 className="text-[1.3rem] font-bold text-[var(--text-high)]">M3U / XMLTV direct</h2>
          <Field
            label="URL de la playlist (M3U)"
            name="playlistUrl"
            placeholder="http://exemple.com/get.php?...type=m3u_plus"
            defaultValue={config.playlistUrl}
          />
          <Field
            label="URL du guide (XMLTV) — optionnel"
            name="epgUrl"
            placeholder="http://exemple.com/xmltv.php?..."
            defaultValue={config.epgUrl}
          />
          <button
            data-focusable
            type="submit"
            className="focusable mt-[0.4rem] rounded-[var(--radius)] px-[1.4rem] py-[0.8rem] text-[1.1rem] font-bold text-black"
            style={{ background: "var(--accent-grad)" }}
          >
            Enregistrer
          </button>
        </form>

        {/* Xtream Codes */}
        <form action={saveSource} className="flex flex-col gap-[0.8rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
          <input type="hidden" name="mode" value="xtream" />
          <h2 className="text-[1.3rem] font-bold text-[var(--text-high)]">Xtream Codes</h2>
          <Field label="Serveur" name="server" placeholder="http://serveur:8080" />
          <Field label="Identifiant" name="username" placeholder="utilisateur" />
          <Field label="Mot de passe" name="password" placeholder="••••••••" />
          <button
            data-focusable
            type="submit"
            className="focusable mt-[0.4rem] rounded-[var(--radius)] px-[1.4rem] py-[0.8rem] text-[1.1rem] font-bold text-black"
            style={{ background: "var(--accent-grad)" }}
          >
            Connecter
          </button>
        </form>
      </div>

      {/* Display */}
      <h2 className="mb-[0.8rem] mt-[2rem] text-[1.3rem] font-bold text-[var(--text-high)]">Affichage</h2>
      <DisplaySettings />

      <form action={resetSource} className="mt-[2rem]">
        <button
          data-focusable
          type="submit"
          className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-medium)]"
        >
          Réinitialiser la source
        </button>
      </form>
    </div>
  );
}
