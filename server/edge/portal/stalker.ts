/*
 * Stalker / MAG portal surface.
 *
 * MAG-style boxes identify themselves with a MAC address in a cookie, ask for a
 * token, then request a playable link per channel. This implements the subset
 * those boxes actually call; unknown actions answer with an empty `js` payload
 * rather than an error, because a set-top box that gets a 404 usually gives up
 * on the whole portal.
 *
 * Security note, stated plainly: a MAC in a cookie is an identifier, not a
 * secret. Anyone who knows a registered MAC can present it. That is how the
 * protocol works — the mitigations here are the ones available: the MAC must be
 * registered AND have a live subscription, links are issued against a
 * short-lived token bound to that MAC, and the connection limit still applies.
 */

import { randomBytes } from "node:crypto";
import type http from "node:http";
import { deliverLive, deliverVod, sendJson } from "../http/deliver.ts";
import { formatRemaining } from "./plans.ts";
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
import { normalizeMac, type AuthResult } from "./devices.ts";

const TOKEN_TTL_MS = 12 * 3_600_000;

interface Ticket {
  mac: string;
  expiresAt: number;
}

/** `mac=00%3A1A%3A79%3AAA%3ABB%3ACC; stb_lang=en` → the MAC. */
export function macFromCookie(cookie: string | undefined): string | null {
  if (!cookie) return null;
  for (const part of cookie.split(";")) {
    const [name, ...rest] = part.trim().split("=");
    if (name.toLowerCase() !== "mac") continue;
    try {
      return normalizeMac(decodeURIComponent(rest.join("=")));
    } catch {
      return null;
    }
  }
  return null;
}

export function createStalkerRouter(context: PortalContext) {
  const tickets = new Map<string, Ticket>();

  function issueTicket(mac: string): string {
    const token = randomBytes(16).toString("hex");
    tickets.set(token, { mac, expiresAt: context.wallClock.now() + TOKEN_TTL_MS });
    return token;
  }

  function macFromTicket(token: string | null): string | null {
    if (!token) return null;
    const ticket = tickets.get(token);
    if (!ticket) return null;
    if (ticket.expiresAt <= context.wallClock.now()) {
      tickets.delete(token);
      return null;
    }
    return ticket.mac;
  }

  function bearer(req: http.IncomingMessage): string | null {
    const header = req.headers.authorization ?? "";
    return header.startsWith("Bearer ") ? header.slice(7).trim() : null;
  }

  /** MAC comes from the cookie, or from the token issued to that cookie. */
  function identify(req: http.IncomingMessage): string | null {
    return macFromCookie(req.headers.cookie) ?? macFromTicket(bearer(req));
  }

  function authorise(mac: string | null): AuthResult {
    if (!mac) return { ok: false, reason: "unknown-device" };
    const result = context.repo.authenticateMac(mac, context.wallClock.now());
    if (result.ok) {
      context.onEvent?.({
        type: "portal-auth",
        portal: "stalker",
        device: result.status.device.id,
        label: result.status.device.label,
      });
    } else {
      context.onEvent?.({ type: "portal-denied", portal: "stalker", reason: result.reason });
    }
    return result;
  }

  function js(res: http.ServerResponse, payload: unknown): void {
    sendJson(res, 200, { js: payload });
  }

  async function portal(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    url: URL
  ): Promise<void> {
    const type = url.searchParams.get("type") ?? "";
    const action = url.searchParams.get("action") ?? "";
    const mac = identify(req);

    // The handshake happens before anything is known about entitlement: a box
    // must be able to get a token and then be told it has no subscription.
    if (type === "stb" && action === "handshake") {
      const token = mac ? issueTicket(mac) : "";
      js(res, { token, random: randomBytes(8).toString("hex") });
      return;
    }

    const auth = authorise(mac);
    if (!auth.ok) {
      if (type === "stb" && action === "get_profile") {
        // status != 0 is how a MAG box learns it is not (or no longer) allowed.
        js(res, {
          id: 0,
          name: "",
          status: 1,
          block_reason: DENIAL_MESSAGES[auth.reason],
          mac: mac ?? "",
          phone: DENIAL_MESSAGES[auth.reason],
        });
        return;
      }
      js(res, {});
      return;
    }

    const status = auth.status;
    const pack = auth.package;
    const now = context.wallClock.now();
    const expires = status.subscription?.expiresAt ?? now;

    switch (`${type}:${action}`) {
      case "stb:get_profile":
      case "stb:do_auth": {
        js(res, {
          id: status.device.id,
          name: status.device.label || status.device.mac || "",
          status: 0,
          mac: status.device.mac ?? "",
          // MAG firmwares display `phone` on the info screen — portals have
          // used it to show the expiry date for years.
          phone: formatTimestamp(expires),
          expire_billing_date: formatTimestamp(expires),
          play_token: bearer(req) ?? "",
          block_msg: "",
          watchdog_timeout: 120,
          timeslot: 0,
        });
        return;
      }
      case "stb:get_localization":
        js(res, { locale: "fr_FR", timezone: "UTC" });
        return;
      case "account_info:get_main_info": {
        js(res, {
          mac: status.device.mac ?? "",
          phone: formatTimestamp(expires),
          end_date: formatTimestamp(expires),
          tariff_plan: status.subscription?.plan ?? "",
          status: status.state,
          remaining: formatRemaining(status.remainingMs),
        });
        return;
      }
      case "itv:get_genres": {
        const channels = await packageChannels(context, pack);
        const groups = [...new Set(channels.map((channel) => channel.group ?? "Général"))];
        js(
          res,
          groups.map((group, index) => ({
            id: String(numericId(group)),
            title: group,
            alias: group.toLowerCase(),
            number: String(index + 1),
          }))
        );
        return;
      }
      case "itv:get_all_channels":
      case "itv:get_ordered_list": {
        const base = baseUrl(context, req.headers.host);
        const token = bearer(req) ?? (mac ? issueTicket(mac) : "");
        const channels = await packageChannels(context, pack);
        const data = channels.map((channel, index) => ({
          id: String(numericId(channel.id)),
          name: channel.name,
          number: String(index + 1),
          tv_genre_id: String(numericId(channel.group ?? "Général")),
          logo: channel.logo ?? "",
          censored: 0,
          cmd: `ffmpeg ${base}/stalker/stream/${token}/live/${numericId(channel.id)}`,
          use_http_tmp_link: 1,
          allow_local_timeshift: 0,
        }));
        js(res, { total_items: data.length, max_page_items: data.length, selected_item: 0, cur_page: 1, data });
        return;
      }
      case "vod:get_categories": {
        const categories = context.catalog
          .listCategories("movie")
          .filter((category) => category.enabled && pack.vodEnabled);
        js(
          res,
          categories.map((category) => ({
            id: String(category.id),
            title: category.name,
            alias: category.name.toLowerCase(),
          }))
        );
        return;
      }
      case "vod:get_ordered_list": {
        if (!pack.vodEnabled) {
          js(res, { total_items: 0, max_page_items: 0, data: [] });
          return;
        }
        const base = baseUrl(context, req.headers.host);
        const token = bearer(req) ?? (mac ? issueTicket(mac) : "");
        const categoryId = url.searchParams.get("category");
        const titles = context.catalog.titles({
          kind: "movie",
          enabledOnly: true,
          categoryId: categoryId && categoryId !== "*" ? Number(categoryId) : undefined,
          limit: 500,
        });
        const data = titles.map((title) => ({
          id: String(title.id),
          name: title.title,
          o_name: title.title,
          year: title.year ? String(title.year) : "",
          screenshot_uri: title.poster ?? "",
          description: title.plot ?? "",
          rating_imdb: title.rating ?? "",
          category_id: String(title.categoryId ?? ""),
          cmd: `${base}/stalker/stream/${token}/movie/${title.id}`,
        }));
        js(res, { total_items: data.length, max_page_items: data.length, selected_item: 0, cur_page: 1, data });
        return;
      }
      case "itv:create_link":
      case "vod:create_link": {
        const cmd = url.searchParams.get("cmd") ?? "";
        // The box echoes back the cmd we handed it; re-issuing it against a
        // fresh token keeps links short-lived.
        const token = bearer(req) ?? (mac ? issueTicket(mac) : "");
        const rewritten = cmd.replace(/\/stalker\/stream\/[^/]+\//, `/stalker/stream/${token}/`);
        js(res, { id: 0, cmd: rewritten || cmd, streamer_id: 0 });
        return;
      }
      case "stb:log":
      case "stb:set_played":
      case "watchdog:get_events":
        js(res, {});
        return;
      default:
        js(res, {});
        return;
    }
  }

  async function stream(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    token: string,
    kind: string,
    rawId: string
  ): Promise<void> {
    const mac = macFromTicket(token);
    const auth = authorise(mac);
    if (!auth.ok) {
      sendJson(res, 403, { error: "forbidden", detail: DENIAL_MESSAGES[auth.reason] });
      return;
    }
    if (!withinConnectionLimit(context, auth.status)) {
      res.setHeader("retry-after", "5");
      sendJson(res, 429, { error: "connection_limit" });
      return;
    }

    const id = Number(rawId.replace(/\.[a-z0-9]+$/i, ""));
    const owner = { deviceId: auth.status.device.id, label: auth.status.device.label };

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

    if (!auth.package.vodEnabled) {
      sendJson(res, 403, { error: "vod_not_included" });
      return;
    }
    const title = context.catalog.title(id);
    const vodStream = title ? context.catalog.preferredStream(title.id) : null;
    if (!title || !vodStream) {
      sendJson(res, 404, { error: "unknown_title" });
      return;
    }
    await deliverVod({
      cache: context.cache,
      req,
      res,
      contentType: vodStream.container === "mkv" ? "video/x-matroska" : "video/mp4",
      target: {
        url: vodStream.url,
        identity: context.edge.accounts.identity(auth.package.accountId),
        acquireLease: () => context.edge.acquireVodLease(auth.package.accountId),
      },
    });
  }

  async function handle(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    url: URL
  ): Promise<boolean> {
    if (url.pathname === "/portal.php" || url.pathname === "/stalker_portal/server/load.php") {
      await portal(req, res, url);
      return true;
    }
    const match = /^\/stalker\/stream\/([^/]+)\/(live|movie)\/(.+)$/.exec(url.pathname);
    if (match) {
      await stream(req, res, match[1], match[2], decodeURIComponent(match[3]));
      return true;
    }
    return false;
  }

  return { handle, issueTicket, tickets };
}

export type StalkerRouter = ReturnType<typeof createStalkerRouter>;
