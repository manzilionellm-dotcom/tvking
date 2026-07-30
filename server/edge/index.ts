/** Public surface of the edge proxy. */

export {
  ManualClock,
  ManualWallClock,
  systemClock,
  systemWallClock,
  type Clock,
  type WallClock,
} from "./clock.ts";
export { AbortedError, Deferred, Mutex, Semaphore, withAbort } from "./sync.ts";
export { SingleFlight } from "./singleflight.ts";
export { RingBuffer, type RingBufferOptions, type StreamChunk } from "./ring-buffer.ts";
export { Broadcaster, Subscription, type SubscribeOptions } from "./broadcast.ts";
export { TokenBucket, pace, type PaceOptions, type TokenBucketOptions } from "./token-bucket.ts";
export {
  MASTER_DEVICE_PROFILES,
  assertMirrorsMasterSignature,
  isMasterDeviceName,
  masterDevice,
  masterSignature,
  type MasterDeviceName,
  CLIENT_IDENTITY_HEADERS,
  DOWNSTREAM_STRIPPED_HEADERS,
  HOP_BY_HOP_HEADERS,
  UPSTREAM_FORWARD_ALLOWLIST,
  assertNoClientMetadata,
  buildUpstreamHeaders,
  connectionListedHeaders,
  inspectClientMetadata,
  redactUrl,
  sanitizeDownstreamHeaders,
  type HeaderBag,
  type SanitizeResult,
  type UpstreamIdentity,
} from "./sanitize.ts";
export {
  FetchOriginTransport,
  UpstreamError,
  assertAllowedOrigin,
  countingTransport,
  createCounters,
  type OriginRequest,
  type OriginResponse,
  type OriginTransport,
  type UpstreamCounters,
} from "./origin.ts";
export {
  StreamHub,
  type HubEvent,
  type HubState,
  type HubStats,
  type JoinOptions,
  type ReconnectPolicy,
  type StreamHubOptions,
} from "./hub.ts";
export { parseM3u, slugify, type M3uEntry, type M3uPlaylist } from "./m3u.ts";
export {
  SlotPool,
  type ContentionPolicy,
  type SlotEvent,
  type SlotHolder,
  type SlotLease,
  type SlotPoolOptions,
} from "./slots.ts";
export {
  AccountError,
  AccountRegistry,
  type AccountSnapshot,
  type MasterAccount,
  type MasterAccountInput,
  type PlaylistFetcher,
} from "./accounts.ts";
export { createAdminRouter, type AdminOptions, type AdminRouter } from "./admin.ts";
export { DASHBOARD_HTML } from "./dashboard.ts";
export {
  DEFAULT_ACCOUNT,
  EdgeProxy,
  UnknownStreamError,
  parseStreamId,
  type AccountOverview,
  type EdgeOverview,
  type SessionSnapshot,
  type EdgeConfig,
  type EdgeEvent,
  type EdgeStats,
  type EdgeSubscription,
  type OriginResolver,
  type OriginTarget,
} from "./edge.ts";
export { createEdgeServer, type EdgeServerOptions, type PortalRouter } from "./server.ts";
export { Database, migrate, openDatabase, schemaVersion, type Row } from "./db/database.ts";
export { MIGRATIONS, type Migration } from "./db/schema.ts";
export {
  PLANS,
  PLAN_IDS,
  addMonthsUtc,
  formatRemaining,
  isPlanId,
  planExpiry,
  renewalStart,
  type Plan,
  type PlanId,
} from "./portal/plans.ts";
export {
  PortalError,
  PortalRepository,
  generateCredentials,
  hashPassword,
  isMac,
  normalizeMac,
  verifyPassword,
  type AccessState,
  type AuthFailure,
  type AuthResult,
  type DeviceInput,
  type DeviceRecord,
  type DeviceStatus,
  type PackageInput,
  type PackageRecord,
  type SubscriptionRecord,
} from "./portal/devices.ts";
export { ExpirationEnforcer, type EnforcerOptions, type SweepResult } from "./portal/enforcer.ts";
export {
  DENIAL_MESSAGES,
  numericId,
  packageChannels,
  type PortalContext,
  type PortalEvent,
} from "./portal/context.ts";
export { createXtreamRouter, type XtreamRouter } from "./portal/xtream.ts";
export { createStalkerRouter, macFromCookie, type StalkerRouter } from "./portal/stalker.ts";
export {
  classify,
  looksLikeVod,
  normalizeCategory,
  normalizeTitle,
  type ClassifiedItem,
  type VodKind,
} from "./vod/classify.ts";
export {
  LibraryError,
  VodLibrary,
  type Assignment,
  type AssignmentTarget,
  type ImportEntry,
  type ItemPatch,
  type ItemQuery,
  type VodCategory,
  type VodItem,
  type VodSource,
  type VodState,
} from "./vod/library.ts";
export {
  VodDownloader,
  type DownloadEvent,
  type DownloadReport,
  type DownloaderOptions,
  type ImportReport,
} from "./vod/downloader.ts";
export {
  CONTENT_TYPES,
  VodError,
  deliverFile,
  deliverLive,
  parseRange,
  sendJson,
  sendText,
  type FileDeliveryOptions,
  type LiveDeliveryOptions,
} from "./http/deliver.ts";
export {
  ConfigError,
  buildResolver,
  loadConfig,
  parseAccounts,
  type EdgeRuntimeConfig,
  type Env,
} from "./config.ts";
