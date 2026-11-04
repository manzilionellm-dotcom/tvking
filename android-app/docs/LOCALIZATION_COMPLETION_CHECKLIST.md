# ZUNO / 7 MOTION — Localization acceptance criteria

Status: NOT COMPLETE. This document records the required implementation and verification work; it does not claim translations have shipped.

## Requirements

- Follow the device language by default; allow an explicit override and a System option.
- Translate all first-party UI strings: onboarding, login, Xtream/M3U, player, Cast, EPG, playlists, settings, trial, subscription, errors, accessibility labels, dialogs, notifications and WhatsApp support templates.
- Keep user-supplied titles, URLs, usernames, passwords, MAC addresses and channel metadata unchanged.
- Use generated ARB localization resources and typed keys, never runtime machine translation of credentials or URLs.
- Support correct RTL layout for Arabic and test text scaling and keyboard insets on small screens.
- Do not advertise a language until its ARB resource is complete and validated. English is the fallback for unsupported device languages.
- Prioritize Somali (so), German (de), Italian (it), Portuguese (pt), plus all currently declared locales.
- WhatsApp: prepare a localized message with opt-in review before sending; never include passwords, tokens, private playlist URLs or other secrets.

## Release gate

1. Inventory all user-visible literals across Flutter screens and platform-specific strings.
2. Add every key to the template ARB and translate every key for each advertised locale.
3. Validate ARB placeholders, plurals, escaping, generated localization and missing keys in CI.
4. Run flutter analyze, flutter test and widget tests for all locales; check RTL and keyboard visibility.
5. Test on real Android phone and TV, including Cast playback; build and sign an APK only after checks pass.
6. Record tested commit SHA and APK checksum; no production deployment without approval.
