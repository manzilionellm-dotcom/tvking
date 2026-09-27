import { ZUNO_APP_ONLY_BLURB, ZUNO_APP_ONLY_PHRASE } from "../../lib/legal-copy";

type Props = {
  /** home / faq = large emphasis; default = compact strip */
  variant?: "hero" | "banner" | "compact";
  className?: string;
};

export default function AppOnlyNotice({
  variant = "banner",
  className = "",
}: Props) {
  if (variant === "hero") {
    return (
      <aside
        className={`rounded-2xl border border-amber-400/25 bg-amber-400/10 px-4 py-3.5 text-left sm:px-5 ${className}`}
        role="note"
      >
        <p className="text-sm font-semibold text-amber-100 sm:text-base">
          {ZUNO_APP_ONLY_PHRASE}
        </p>
        <p className="mt-1.5 text-xs leading-relaxed text-amber-100/70 sm:text-sm">
          {ZUNO_APP_ONLY_BLURB}
        </p>
      </aside>
    );
  }

  if (variant === "compact") {
    return (
      <p className={`text-xs leading-relaxed text-white/40 ${className}`}>
        {ZUNO_APP_ONLY_PHRASE}
      </p>
    );
  }

  return (
    <aside
      className={`rounded-xl border border-white/10 bg-white/[0.03] px-3.5 py-2.5 text-center ${className}`}
      role="note"
    >
      <p className="text-xs font-medium text-white/65 sm:text-sm">
        {ZUNO_APP_ONLY_PHRASE}
      </p>
    </aside>
  );
}
