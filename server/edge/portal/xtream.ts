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
import { CONTENT_TYPES, VodError, deliverFile, deliverLive, sendJson, sendText } from "../http/deliver.ts";
import { PLANS } from "./plans.ts";
import {
  DENIAL_MESSAGES,
  baseUrl,
  findChannelByNumericId,
  formatTimestamp,
  numericId,
  packageChannels,
  visibleVod,
  withinConnectionLimit,
  type PortalContext,
} from "./context.ts";
import type { AuthResult, DeviceStatus } from "./devices.ts";

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
        // Only folders holding something this subscriber was actually given.
        const categories = pack.vodEnabled
          ? context.library.visibleCategories(
              { packageId: pack.id, deviceId: status.device.id },
              kind
            )
          : [];
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
        const kind = action === "get_vod_streams" ? "movie" : "series";
        const categoryId = url.searchParams.get("category_id");
        const items = visibleVod(context, status, {
          kind,
          categoryId: categoryId ? Number(categoryId) : undefined,
        });
        sendJson(
          res,
          200,
          items.map((item, index) => ({
            num: index + 1,
            name: item.year ? `${item.title} (${item.year})` : item.title,
            title: item.title,
            year: item.year || "",
            stream_type: kind === "movie" ? "movie" : "series",
            stream_id: item.id,
            series_id: item.id,
            stream_icon: item.poster ?? "",
            cover: item.poster ?? "",
            added: String(Math.floor((item.downloadedAt ?? item.updatedAt) / 1000)),
            category_id: String(item.categoryId ?? ""),
            container_extension: item.container ?? "mp4",
            direct_source: "",
          }))
        );
        return;
      }
      case "get_vod_info":
      case "get_series_info": {
        const id = Number(url.searchParams.get("vod_id") ?? url.searchParams.get("series_id"));
        // Resolved through the visibility rules, never straight from the id:
        // guessing an item number must not hand over someone else's library.
        const item = visibleVod(context, status).find((candidate) => candidate.id === id);
        if (!item) {
          sendJson(res, 200, {});
          return;
        }
        sendJson(res, 200, {
          info: {
            name: item.title,
            year: item.year || "",
            cover_big: item.poster ?? "",
            movie_image: item.poster ?? "",
            genre: item.category ?? "",
          },
          movie_data: {
            stream_id: item.id,
            name: item.title,
            added: String(Math.floor((item.downloadedAt ?? item.updatedAt) / 1000)),
            category_id: String(item.categoryId ?? ""),
            container_extension: item.container ?? "mp4",
          },
          episodes:
            item.season === null
              ? []
              : [
                  {
                    id: String(item.id),
                    episode_num: item.episode,
                    season: item.season,
                    title: item.title,
                    container_extension: item.container ?? "mp4",
                  },
                ],
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

    for (const item of visibleVod(context, auth.status)) {
      lines.push(
        `#EXTINF:-1 tvg-name="${item.title}" tvg-logo="${item.poster ?? ""}"` +
          ` group-title="${item.category ?? "VOD"}",${item.title}`
      );
      lines.push(
        `${base}/movie/${user.username}/${user.password}/${item.id}.${item.container ?? "mp4"}`
      );
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

    // VOD is byte-served off local disk; the session book tracks live streams.
    void owner;
    const item = visibleVod(context, auth.status).find((candidate) => candidate.id === id);
    if (!item || !item.filePath) {
      sendJson(res, 404, { error: "unknown_title" });
      return;
    }
    try {
      await deliverFile({
        filePath: item.filePath,
        req,
        res,
        contentType: CONTENT_TYPES[item.container ?? "mp4"] ?? "video/mp4",
      });
    } catch (error) {
      if (error instanceof VodError) {
        sendJson(res, error.status, { error: "not_downloaded", detail: error.message });
        return;
      }
      throw error;
    }
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
