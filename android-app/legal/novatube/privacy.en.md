# Privacy Policy — NOVATUBE

Last updated: 14 November 2026

## 1. NOVATUBE and contact

NOVATUBE is a media player for Android phones and tablets. You add your own M3U or Xtream sources. The application does not provide a content catalogue or create a remote NOVATUBE account.

This policy concerns the Google Play version of NOVATUBE, identified as com.sevenmotion.novatube. For questions about your data, contact the publisher at lionel930031@gmail.com.

## 2. Data on your device

Your profiles, sources and provider credentials, settings, favourites, playback information and programme-guide data are kept on your device to operate the player.

Recordings are created on your device. Exporting to the gallery or sharing with another application may create a copy outside NOVATUBE’s private storage.

NOVATUBE’s diagnostic log stays on your device in this version. NOVATUBE does not automatically upload this log or make a cloud backup of your sources. Google Cast technical events are described below.

When system authentication is used, Android performs verification. NOVATUBE does not receive your fingerprint or facial templates.

## 3. Connections to your sources

Importing and refreshing sources, programme listings, artwork and playback contact addresses supplied by your source. Requests may include its URL and credentials required by your provider. The contacted server also receives connection information, including the IP address.

Xtream credentials belong to your provider account, not a NOVATUBE account. Your provider applies its own data handling and retention terms.

## 4. Casting and the streaming relay

Cast and DLNA device discovery uses your local network. When you choose a device, NOVATUBE sends it the information needed for playback. Some playback paths use a local relay on your phone or tablet.

Some MPEG-TS streams also pass through the HTTPS relay at api.zuno8k.com, hosted with Cloudflare. The relay receives the complete stream URL to authorise and route playback. This URL may contain your provider username and password.

The relay forwards video continuously without creating a video library or archive. This does not mean that every item associated with a request is processed only in memory.

To limit abuse, the service stores a key containing the IP address, a request counter and a timestamp in a Cloudflare D1 database.

## 5. Google Cast and voice search

Google Cast sends Google anonymous technical usage events to improve its SDK: discovery and session events, and technical information about the mobile device and application. Transmission is encrypted. This collection cannot be disabled in NOVATUBE, and the SDK provides no individual deletion control. Google describes brief retention followed by aggregation before deletion.

When you use voice search, NOVATUBE opens Android’s available recognition service. That service handles speech under its own terms; NOVATUBE receives recognised text to search your sources. Search does not use a remote NOVATUBE AI service.

## 6. Purposes and recipients

Data supports the player, source import and playback, casting, local diagnostics and relay security. Google Cast events support SDK technical analytics.

Depending on the features used, recipients include your source provider, playback devices, Cloudflare for the relay and this page, Google for Cast, Android’s speech recognition service and applications you choose when sharing a file.

NOVATUBE has no integrated advertising in this version. Independent practices of your content provider remain governed by its own terms.

## 7. Communication security

Connections to the api.zuno8k.com relay and this page use HTTPS. Sources you provide may use HTTP or HTTPS, and some local Cast communications use HTTP. Not every communication involving your sources is therefore necessarily encrypted.

The application must be able to read information needed to access your streams. This is not end-to-end encryption. Do not include provider passwords in a support question or in this page’s address.

## 8. Retention and deletion

Local data remains on your device for use by the application. You can remove sources and profiles through the available controls or clear NOVATUBE’s data in Android settings. Recordings and exported copies remain in their locations until deleted.

Cast relay anti-abuse entries currently have no defined automatic deletion deadline. The service does not perform age-based purging of those entries. They may therefore remain without an automatic time limit. The request counter’s calculation window is not a deletion period.

Stream URLs are used to authorise and route playback. No maximum retention period is guaranteed here for all potential technical traces of those requests. We do not claim that this processing is exclusively ephemeral.

Earlier database states may also remain in Cloudflare’s backup and recovery systems under their own retention rules.

Clearing NOVATUBE locally does not necessarily erase exported videos, shared copies, provider data, relay anti-abuse entries or Google Cast events. The application does not offer a remote deletion command for relay data.

## 9. Hosting this page and support

This page is hosted on a Cloudflare service separate from the streaming relay. It has no form, advertising cookie or advertising analytics tool, and does not ask for a media source.

Cloudflare receives your IP address and connection information needed to deliver and protect the page. Sampled technical logs and traces help check its operation. Messages produced by the site’s code contain only a page category and response status; platform traces may contain request metadata.

Workers logs and traces configured for this site are retained for up to seven days according to Cloudflare’s documentation. This statement concerns Workers Observability, not every other technical processing activity of the host.

Emailing support sends your sender address and the information you choose to provide to the publisher’s mailbox to handle your question. This policy does not guarantee an automatic deletion period for those messages.

## 10. Questions and changes

For questions about this policy or your data, email lionel930031@gmail.com. Sending a message does not automatically delete data held by the relay, your providers or Google. This policy does not limit rights granted by applicable law.

This page will be updated when the described practices change. The date above identifies its last update.

## Provider information

- [Google Cast](https://developers.google.com/cast/docs/android_sender/data_disclosure)
- [Cloudflare Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)
- [Cloudflare Workers Traces](https://developers.cloudflare.com/workers/observability/traces/)
- [Cloudflare D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/)

