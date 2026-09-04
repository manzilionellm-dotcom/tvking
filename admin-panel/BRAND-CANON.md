# Brand canon (public copy)

Public-facing labels only. **Package / application IDs are frozen** — never
rename them (that kills existing installs).

| Surface | Name |
|---|---|
| Company / site | **7 MOTION** |
| App display (grand public, mobile) | **The Few** |
| App display (living-room TV) | **The Few** or **7 MOTION TV** |
| Adult (keep separate) | **Privé** only |

Retired in public copy: BLACK7 ROYAL, Nova / NOVA+, Red Room, DeFew as a
user-visible product name, SEVEN as a separate brand.

## Package IDs — frozen (do not rename)

- `com.manzilionellm.tvking` — The Few (mobile)
- `com.manzilionellm.tvking.tv` — TV living-room (may still ship as DeFew internally)
- `com.manzilionellm.tvking.prive` (and siblings) — Privé

URL aliases (`/tv`, `/defewtv`, `/royal`, `/black7`, `?app=redroom`, …) stay
as download/route compatibility. Only the **displayed** name changes.

Internal D1 / panel ids (`app_7motion`, `app_thefew_tv`) stay as-is.

## This cleanup — files touched

1. `admin-panel/BRAND-CANON.md` (this file)
2. `admin-panel/src/pages/ThemePage.tsx`
3. `admin-panel/src/pages/AppsPage.tsx`
4. `cloudflare/schema.sql`
5. `cloudflare/api_v1.js`
6. `cloudflare/worker.js`
7. `cloudflare/cast_receiver.js`

Not touched: `lib/`, Android/iOS package IDs, APK URLs, download aliases,
pipelines, PR #15 family logic.
