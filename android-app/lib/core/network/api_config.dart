/// One backend for all panel-controlled APIs (no Vercel UI URL).
/// API_BASE must be an HTTPS origin without a trailing slash.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://seven-motion-backend.manzilionel-lm.workers.dev',
);
const Map<String, String> kNoCacheHeaders = <String, String>{
  'Accept': 'application/json',
  'Cache-Control': 'no-cache, no-store',
  'Pragma': 'no-cache',
};
