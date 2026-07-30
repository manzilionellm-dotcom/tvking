/*
 * Xtream Codes API surface.
 *
 * This is the dialect virtually every IPTV player speaks, so implementing it is
 * what lets an existing app point at this proxy instead of at the provider —
 * which is the whole point of the edge: the player talks to the LAN, the LAN
 * talks to the provider once.
 *
 * Only the read paths that players actually call are implemented. Field names
 * and types follow the wire format (numbers as strings, "1"/"0" booleans),
 * because players parse them strictly.
 */

import type http from "node:http";
import { deliverLive, deliverVod, sendJson, sendText } from "../http/deliver.ts";
import { PLANS } from "./plans.ts";
import {
  DENIAL_MESSAGES,
  baseUrl,
  findChannelByNumericId,
  formatTimestamp,
  numericId,
  packageChannels,
  withinConnectionLimit,
  type PortalContext,
} from "./context.ts";
import type { AuthResult, DeviceStatus, PackageRecord } from "./devices.ts";

interface Credentials {
  username: string;
  password: string;
}

function credentials(url: URL): Credentials | null {
  const username = url.searchParams.get("username");
  const password = url.searchParams.get("password");
  return username && password ? { username, password } : null;
}

/** Handles /player_api.php, /get.php, /xmltv.php, /live/…, /movie/…, /series/…. */
export function createXtreamRouter(context: PortalContext) {
  function authorise(user: Credentials): AuthResult {
    const result = context.repo.authenticateXtream(
      user.username,
      user.password,
      context.wallClock.now()
    );
    if (result.ok) {
      context.onEvent?.({
        type: "portal-auth",
        portal: "xtream",
        device: result.status.device.id,
        label: result.status.device.label,
      });
    } else {
      context.onEvent?.({ type: "portal-denied", portal: "xtream", reason: result.reason });
    }
    return result;
  }

  function userInfo(status: DeviceStatus, user: Credentials, host: string | undefined) {
    const now = context.wallClock.now();
    const expires = status.subscription?.expiresAt ?? now;
    const plan = status.subscription?.plan;
    const base = new URL(baseUrl(context, host));
    return {
      user_info: {
        username: user.username,
        password: user.password,
        message: "",
        auth: 1,
        status: status.state === "active" ? "Active" : "Expired",
        exp_date: String(Math.floor(expires / 1000)),
        is_trial: plan && PLANS[plan].trial ? "1" : "0",
        active_cons: String(context.edge.sessionsForDevice(status.device.id).length),
        created_at: String(Math.floor(status.device.createdAt / 1000)),
        max_connections: String(status.device.maxConnections),
        allowed_output_formats: ["ts"],
      },
      server_info: {
        url: base.hostname,
        port: base.port || "80",
        https_port: "",
        server_protocol: base.protocol.replace(":", ""),
        rtmp_port: "",
        timezone: "UTC",
        timestamp_now: Math.floor(now / 1000),
        time_now: formatTimestamp(now),
      },
    };
  }

  async function playerApi(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    url: URL
  ): Promise<void> {
    const user = credentials(url);
    if (!user) {
      sendJson(res, 200, { user_info: { auth: 0, message: "missing credentials" } });
      return;
    }
    const auth = authorise(user);
    if (!auth.ok) {
      // Players expect auth:0 with HTTP 200 rather than a 401 body they cannot parse.
      sendJson(res, 200, {
        user_info: { auth: 0, status: "Disabled", message: DENIAL_MESSAGES[auth.reason] },
      });
      return;
    }

    const action = url.searchParams.get("action");
    const status = auth.status;
    const pack = auth.package;

    if (!action) {
      sendJson(res, 200, userInfo(status, user, req.headers.host));
      return;
    }

    switch (action) {
      case "get_live_categories": {
        const channels = await packageChannels(context, pack);
        const groups = [...new Set(channels.map((channel) => channel.group ?? "Général"))];
        sendJson(
          res,
          200,
          groups.map((group) => ({
            category_id: String(numericId(group)),
            category_name: group,
            parent_id: 0,
          }))
        );
        return;
      }
      case "get_live_streams": {
        const wanted = url.searchParams.get("category_id");
        const channels = await packageChannels(context, pack);
        const streams = channels
          .filter((channel) =>
            wanted ? String(numericId(channel.group ?? "Général")) === wanted : true
          )
          .map((channel, index) => ({
            num: index + 1,
            name: channel.name,
            stream_type: "live",
            stream_id: numericId(channel.id),
            stream_icon: channel.logo ?? "",
            epg_channel_id: channel.attributes["tvg-id"] ?? "",
            added: String(Math.floor(context.wallClock.now() / 1000)),
            category_id: String(numericId(channel.group ?? "Général")),
            custom_sid: "",
            tv_archive: 0,
            direct_source: "",
            tv_archive_duration: 0,
          }));
        sendJson(res, 200, streams);
        return;
      }
      case "get_vod_categories":
      case "get_series_categories": {
        const kind = action === "get_vod_categories" ? "movie" : "series";
        const categories = context.catalog
          .listCategories(kind)
          .filter((category) => category.enabled && pack.vodEnabled);
        sendJson(
          res,
          200,
          categories.map((category) => ({
            category_id: String(category.id),
            category_name: category.name,
            parent_id: 0,
          }))
        );
        return;
      }
      case "get_vod_streams":
      case "get_series": {
        if (!pack.vodEnabled) {
          sendJson(res, 200, []);
          return;
        }
        const kind = action === "get_vod_streams" ? "movie" : "series";
        const categoryId = url.searchParams.get("category_id");
        const titles = context.catalog.titles({
          kind,
          enabledOnly: true,
          categoryId: categoryId ? Number(categoryId) : undefined,
          limit: 1000,
        });
        sendJson(
          res,
          200,
          titles.map((title, index) => ({
            num: index + 1,
            name: title.year ? `${title.title} (${title.year})` : title.title,
            title: title.title,
            year: title.year || "",
            stream_type: kind === "movie" ? "movie" : "series",
            stream_id: title.id,
            series_id: title.id,
            stream_icon: title.poster ?? "",
            cover: title.poster ?? "",
            rating: title.rating ?? "",
            added: String(Math.floor(title.updatedAt / 1000)),
            category_id: String(title.categoryId ?? ""),
            container_extension:
              context.catalog.preferredStream(title.id)?.container ?? "mp4",
            direct_source: "",
          }))
        );
        return;
      }
      case "get_vod_info":
      case "get_series_info": {
        const id = Number(url.searchParams.get("vod_id") ?? url.searchParams.get("series_id"));
        const title = Number.isFinite(id) ? context.catalog.title(id) : null;
        if (!title || !pack.vodEnabled) {
          sendJson(res, 200, {});
          return;
        }
        const streams = context.catalog.streams(title.id);
        sendJson(res, 200, {
          info: {
            name: title.title,
            year: title.year || "",
            cover_big: title.poster ?? "",
            movie_image: title.poster ?? "",
            plot: title.plot ?? "",
            rating: title.rating ?? "",
            genre: title.category ?? "",
          },
          movie_data: {
            stream_id: title.id,
            name: title.title,
            added: String(Math.floor(title.updatedAt / 1000)),
            category_id: String(title.categoryId ?? ""),
            container_extension: streams[0]?.container ?? "mp4",
          },
          episodes: streams
            .filter((stream) => stream.season !== null)
            .map((stream) => ({
              id: String(stream.id),
              episode_num: stream.episode,
              season: stream.season,
              title: `${title.title} S${stream.season}E${stream.episode}`,
              container_extension: stream.container ?? "mp4",
            })),
        });
        return;
      }
      default:
        sendJson(res, 200, []);
        return;
    }
  }

  /** `type=m3u_plus` playlist, the other way players onboard. */
  async function getPlaylist(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    url: URL
  ): Promise<void> {
    const user = credentials(url);
    const auth = user ? authorise(user) : null;
    if (!user || !auth?.ok) {
      sendText(res, 401, "#EXTM3U\n# unauthorised\n", "audio/x-mpegurl");
      return;
    }
    const base = baseUrl(context, req.headers.host);
    const lines = ["#EXTM3U"];

    for (const channel of await packageChannels(context, auth.package)) {
      const id = numericId(channel.id);
      lines.push(
        `#EXTINF:-1 tvg-id="${channel.attributes["tvg-id"] ?? channel.id}" tvg-name="${channel.name}"` +
          ` tvg-logo="${channel.logo ?? ""}" group-title="${channel.group ?? "Général"}",${channel.name}`
      );
      lines.push(`${base}/live/${user.username}/${user.password}/${id}.ts`);
    }

    if (auth.package.vodEnabled) {
      for (const title of context.catalog.titles({ enabledOnly: true, limit: 1000 })) {
        const container = context.catalog.preferredStream(title.id)?.container ?? "mp4";
        lines.push(
          `#EXTINF:-1 tvg-name="${title.title}" tvg-logo="${title.poster ?? ""}"` +
            ` group-title="${title.category ?? "VOD"}",${title.title}`
        );
        lines.push(`${base}/movie/${user.username}/${user.password}/${title.id}.${container}`);
      }
    }

    sendText(res, 200, `${lines.join("\n")}\n`, "audio/x-mpegurl");
  }

  async function stream(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    kind: "live" | "movie" | "series",
    username: string,
    password: string,
    rawId: string
  ): Promise<void> {
    const auth = authorise({ username, password });
    if (!auth.ok) {
      sendJson(res, 403, { error: "forbidden", detail: DENIAL_MESSAGES[auth.reason] });
      return;
    }
    if (!withinConnectionLimit(context, auth.status)) {
      res.setHeader("retry-after", "5");
      sendJson(res, 429, { error: "connection_limit" });
      return;
    }

    const owner = { deviceId: auth.status.device.id, label: auth.status.device.label };
    const id = Number(rawId.replace(/\.[a-z0-9]+$/i, ""));
    if (!Number.isFinite(id)) {
      sendJson(res, 404, { error: "unknown_stream" });
      return;
    }

    if (kind === "live") {
      const channels = await packageChannels(context, auth.package);
      const channel = findChannelByNumericId(channels, id);
      if (!channel) {
        sendJson(res, 404, { error: "unknown_stream" });
        return;
      }
      await deliverLive({
        edge: context.edge,
        streamId: `${auth.package.accountId}/${channel.id}`,
        req,
        res,
        egressBytesPerSecond: context.egressBytesPerSecond,
        owner,
      });
      return;
    }

    await deliverVodTitle(req, res, id, auth.package, owner);
  }

  async function deliverVodTitle(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    titleId: number,
    pack: PackageRecord,
    owner: { deviceId: number; label?: string }
  ): Promise<void> {
    if (!pack.vodEnabled) {
      sendJson(res, 403, { error: "vod_not_included" });
      return;
    }
    const title = context.catalog.title(titleId);
    const stream = title ? context.catalog.preferredStream(title.id) : null;
    if (!title || !stream) {
      sendJson(res, 404, { error: "unknown_title" });
      return;
    }
    void owner; // VOD is byte-served; the session book tracks live streams only.

    await deliverVod({
      cache: context.cache,
      req,
      res,
      contentType: stream.container === "mkv" ? "video/x-matroska" : "video/mp4",
      target: {
        url: stream.url,
        identity: context.edge.accounts.identity(pack.accountId),
        acquireLease: () => context.edge.acquireVodLease(pack.accountId),
      },
    });
  }

  /** Returns true when the request belonged to this portal. */
  async function handle(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    url: URL
  ): Promise<boolean> {
    const path = url.pathname;

    if (path === "/player_api.php") {
      await playerApi(req, res, url);
      return true;
    }
    if (path === "/get.php" || path === "/enigma2.php") {
      await getPlaylist(req, res, url);
      return true;
    }
    if (path === "/xmltv.php") {
      // No EPG source yet; an empty but valid document beats a 404 in players.
      sendText(res, 200, '<?xml version="1.0" encoding="UTF-8"?>\n<tv></tv>\n', "application/xml");
      return true;
    }

    const streamMatch = /^\/(live|movie|series)\/([^/]+)\/([^/]+)\/(.+)$/.exec(path);
    if (streamMatch) {
      const [, kind, username, password, id] = streamMatch;
      await stream(
        req,
        res,
        kind as "live" | "movie" | "series",
        decodeURIComponent(username),
        decodeURIComponent(password),
        decodeURIComponent(id)
      );
      return true;
    }

    return false;
  }

  return { handle };
}

export type XtreamRouter = ReturnType<typeof createXtreamRouter>;
