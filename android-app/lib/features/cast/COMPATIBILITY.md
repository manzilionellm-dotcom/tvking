# 7 MOTION — Cast Compatibility Matrix

Empirical record of which TVs accept which casting strategies, under
real-world IPTV conditions (Xtream MPEG-TS, HLS, redirects, tokens).

> **Status: Phase 1 — collecting data.** Most cells below are empty.
> The "Hypotheses" section near the bottom contains my best protocol-
> based guesses, but the goal is to **overwrite hypotheses with measured
> results** as testers run the in-app diagnostic against real devices.

---

## How testers fill this matrix

1. Install the latest debug APK from
   [`releases/latest`](https://github.com/manzilionellm-dotcom/tvking/releases/latest).
2. Make sure the TV and the phone are on the same WiFi (NOT a guest
   network, NOT a VPN — both break SSDP discovery).
3. Open **Réglages → Cast → Diagnostic cast**.
4. The picker lists discovered receivers. Pick yours. Pick **Standard
   (8 chaînes)**.
5. Hit **Lancer le diagnostic**. The app casts 8 channels back-to-back
   with a 2-second pause between, recording per-channel result.
6. When done, tap **Copier le rapport**. You get a JSON blob in the
   clipboard.
7. Paste it under the right section in **Empirical results** below,
   OR file a GitHub issue tagged `cast-report` with the JSON in a
   `<details>` block. Strip the model/firmware from the snippet if you
   want to stay anonymous (URLs are already redacted by the app).

---

## Strategy legend

The new failover ladder (post-v2 fix for SetAVTransportURI HTTP 500):

| Code | Name | What |
|------|------|------|
| **D+F** | `direct+full` | Stream URL pushed direct to the receiver, full DLNA metadata (PN + OP + FLAGS). Best latency. |
| **R+F** | `relay+full` | URL re-served through phone's local HTTP relay (DLNA headers injected, redirects resolved, auth re-injected). Full metadata. |
| **R+M** | `relay+minimal` | Same relay route, but `protocolInfo` reduced to `http-get:*:<MIME>:*` (no `DLNA.ORG_PN`). For pre-2018 receivers that reject any PN they don't recognise. |
| ❌ | `failed` | Three strategies failed. User offered QR-code web fallback. |

A receiver that wins on **D+F** is "standards-compliant DLNA".
A receiver that needs **R+F** typically has issues with upstream URLs
(auth, redirects) — the relay normalises them.
A receiver that needs **R+M** is a stricter/older renderer that hates
unknown profile names.

---

## Empirical results

> Each section below is a **per-device-model** dossier. One model =
> one canonical row plus optional per-firmware sub-rows. Paste real
> JSON reports as `<details>` blocks underneath the row.

### Samsung (Tizen)

| Model | Firmware | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------|----------|-----------|---------|---|---------|---------------|-------|
| *(pending — paste your test results here)* | | | | | | | |

<details>
<summary>How a Samsung row should look once filled</summary>

```
| Q60T 55" | T-NKLDEUC-1450.7 | 2026-02-15 | e664734 | 8 | 8/8 (100%) | D+F ×7, R+F ×1 | Single R+F win was a tokenized .m3u8 — expected |
```
</details>

### LG webOS

| Model | webOS | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------|-------|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | | |

### Sony Bravia (Android TV)

| Model | Android version | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------|-----------------|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | | |

### Chromecast / Google TV / Android TV with built-in Cast

| Model | OS | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------|----|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | | |

> **Note:** native Cast SDK bridge is not yet implemented. These
> receivers currently fall back to the QR-code web receiver, which
> covers the actual playback path. Discovery (mDNS) works.

### Fire TV (with AirReceiver or BubbleUPnP installed)

| Model | Fire OS | DLNA app | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------|---------|----------|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | | | |

### Cheap Android TV boxes (X96, T95, H96, MiBox-clones)

| Brand/model | Android version | Test Date | App SHA | n | Success | Best Strategy | Notes |
|-------------|-----------------|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | | |

### Older / legacy DLNA renderers (pre-2018)

| Device | Test Date | App SHA | n | Success | Best Strategy | Notes |
|--------|-----------|---------|---|---------|---------------|-------|
| *(pending)* | | | | | | |

### Software receivers (VLC, Kodi, BubbleUPnP server, etc.)

| Software | Version | Host OS | Test Date | n | Success | Best Strategy | Notes |
|----------|---------|---------|-----------|---|---------|---------------|-------|
| *(pending)* | | | | | | | |

---

## Stream-type coverage targets

What "compatible" means per content type. These are **targets** —
deviations show up as failures in the empirical sections above.

| Content type | Target route | If it fails, why |
|--------------|--------------|------------------|
| **H.264 SD MPEG-TS (`.ts`)** | D+F on any modern DLNA | Receiver hates `DLNA.ORG_PN=MPEG_TS_SD_NA_ISO` → bump to R+M |
| **H.264 HD MPEG-TS** | D+F | Bitrate too high for receiver decoder → no relay can fix; user must pick lower-quality variant |
| **HEVC / H.265** | D+F if receiver has H.265 decoder; ❌ otherwise | No on-device transcode (intentional — APK weight). User must pick H.264 variant. |
| **HLS (`.m3u8`)** | Most DLNA receivers don't speak HLS → ❌ on D+F/R+F; web fallback works | DLNA spec doesn't include HLS profile. Some Smart TVs (Samsung 2020+) accept `application/vnd.apple.mpegurl` directly — others 500. |
| **DASH (`.mpd`)** | ❌ on DLNA; web fallback works | Same story as HLS. |
| **MP4 VOD (no auth)** | D+F | Should pass on every receiver. If not, suspect Range header bug. |
| **MP4 VOD with token in query** | R+F (forced by probe — redirects/auth detected) | Direct fails because TV won't reuse the token. Relay re-injects. |
| **Tokenized Xtream `/live/USER/PASS/ID.ts`** | R+F (forced by probe — `/live/` path triggers relay heuristic) | Same |
| **4K (any codec)** | D+F if receiver decoder + bandwidth allow | Phone-to-TV WiFi bottleneck often shows up here. Relay won't help — physical layer issue. |
| **HDR (HDR10 / DV)** | Out of scope for cast | Cast metadata doesn't carry HDR tone-map info. |

---

## Hypotheses (NOT validated — predictions for triage only)

> These cells are populated from protocol knowledge + community
> reports. Treat them as "what we expect" — replace each with real
> data as soon as a tester runs the harness against the device.

| Receiver class | Predicted winning strategy | Reasoning |
|----------------|----------------------------|-----------|
| **Samsung Tizen 2019+** | **D+F** | Tizen 2019+ stack validates `DLNA.ORG_PN` strictly. v1 of the app sent no PN → 500 every time. v2 fix should restore D+F. |
| **LG webOS 4+** | **D+F** | Same root cause as Samsung. The Stop-first + TRANSITIONING poll also fixes a webOS-specific lock-up. |
| **Sony Bravia DLNA** | **D+F→R+F** | Sony renderers prefer `videoBroadcast` object class for live (now emitted), but some firmware versions still need the relay for tokenized URLs. |
| **Sony Android TV (built-in Cast, not DLNA)** | ❌ → web fallback | mDNS discovery sees it but cast SDK not implemented. Web QR works on the built-in browser. |
| **Fire TV + AirReceiver** | **D+F** | AirReceiver is a permissive DLNA renderer — accepts almost any protocolInfo. Already works in v1, should keep working. |
| **Fire TV + BubbleUPnP** | **D+F or R+F** | BubbleUPnP is strict but well-behaved. |
| **Cheap X96/T95 boxes** | **R+F→R+M** | Buggy DLNA stacks (often AllShare-derived). The minimal metadata fallback catches the worst of them. |
| **VLC in renderer mode** | **R+M** | VLC's renderer mode advertises a narrow Sink. Any PN it doesn't recognise → fails. Minimal works. |
| **Kodi UPnP** | **D+F** | Kodi accepts almost anything. |
| **Roku** | Not DLNA — uses ECP transport directly. See `roku_ecp_transport.dart`. |
| **AppleTV (no AirReceiver)** | ❌ → web fallback | No public AirPlay-receiver API for non-Apple senders. |

---

## Known limitations & non-goals

- **No on-device transcoding.** Intentional. Adds 30+ MB to the APK
  for a long-tail problem. If a stream's codec is incompatible, we
  refuse rather than fake it. User picks another quality variant.
- **No native Google Cast SDK yet.** Would require a Kotlin + Pigeon
  bridge + a CI patch step (since `flutter create` regenerates
  `android/` each build). Web fallback covers the same TVs adequately.
- **No AirPlay video.** Apple AirPlay v2 video requires the FairPlay
  authentication chip. The only honest path is to install
  AirReceiver (or similar DLNA app) on the Apple TV and treat it as
  a DLNA renderer.
- **Discovery requires same /24 subnet.** SSDP and mDNS are multicast
  protocols that don't cross VLANs or guest networks. If your phone
  is on a "guest WiFi" and your TV is on the main WiFi, nothing will
  show up — that's a router config issue, not a bug.

---

## Latency targets (P50 on home WiFi, healthy stream)

| Strategy | Target | Hard cap |
|----------|--------|----------|
| D+F | < 1500 ms tap-to-PLAYING | 3000 ms |
| R+F | < 3000 ms | 5000 ms |
| R+M | < 4500 ms | 7000 ms |

The diagnostic screen displays `totalDurationMs` per cast — flag any
session that exceeds the **hard cap** by 2× as a regression.

---

## When to update this file

- A tester pastes a fresh JSON report → update the empirical table for
  that device class.
- A new receiver class shows up in the wild → add a row in **Hypotheses**.
- The cast code changes (new strategy, new metadata mode) → update the
  **Strategy legend**.
- A hypothesis is contradicted by empirical data → **delete** the
  hypothesis row and replace it with the verified row in the empirical
  section.

The matrix is only useful if it stays current. Stale rows are worse
than missing rows.
