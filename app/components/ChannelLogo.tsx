"use client";

import { useState } from "react";

/*
 * Channel logo (1:1 per Android TV card spec). Logos come from arbitrary
 * provider URLs, so we use a plain <img> (not next/image, which would require
 * whitelisting every host) and fall back to the channel's initials on error —
 * no broken-image icons on a 10-foot screen.
 */
export default function ChannelLogo({
  src,
  name,
  size = "3.4rem",
}: {
  src?: string;
  name: string;
  size?: string;
}) {
  const [failed, setFailed] = useState(false);
  const initials = name.replace(/[^\p{L}\p{N} ]/gu, "").trim().slice(0, 2).toUpperCase() || "TV";

  return (
    <span
      className="flex shrink-0 items-center justify-center overflow-hidden rounded-[0.5rem] bg-[var(--surface-3)] text-[0.95rem] font-bold text-[var(--text-medium)]"
      style={{ width: size, height: size }}
    >
      {src && !failed ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt=""
          className="h-full w-full object-contain"
          loading="lazy"
          decoding="async"
          onError={() => setFailed(true)}
        />
      ) : (
        initials
      )}
    </span>
  );
}
