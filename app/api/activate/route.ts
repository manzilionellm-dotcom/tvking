import { NextResponse } from "next/server";
import {
  activationAdminSecret,
  activationApiKey,
  activationApiUrl,
  adminActionForPlan,
  panelActivateBody,
  planFromSCode,
  workerOriginFromActivateUrl,
  type PanelPlan,
} from "../../lib/activate";
import { toPanelMac } from "../../lib/mac";

type Body = {
  s?: string;
  m2?: string;
  /** aliases */
  code?: string;
  mac?: string;
  codes?: string[];
  plan?: string;
};

export async function POST(req: Request) {
  let body: Body;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { ok: false, message: "JSON invalide." },
      { status: 400 },
    );
  }

  const sCode =
    (body.s || "").trim() ||
    (body.code || "").trim() ||
    (Array.isArray(body.codes) ? body.codes.filter(Boolean).join(",") : "");
  const m2Raw = (body.m2 || body.mac || "").trim();

  const mac = toPanelMac(m2Raw);
  if (!mac) {
    return NextResponse.json(
      {
        ok: false,
        message:
          "M2 invalide. Format attendu : MK:XX:XX:XX:XX:XX (identifiant dans Zuno → Réglages).",
      },
      { status: 400 },
    );
  }
  if (!sCode) {
    return NextResponse.json(
      { ok: false, message: "S code (code d'activation) requis." },
      { status: 400 },
    );
  }

  const plan: PanelPlan | null =
    planFromSCode(body.plan || "") || planFromSCode(sCode);
  if (!plan) {
    return NextResponse.json(
      {
        ok: false,
        message:
          "S code non reconnu. Vérifiez le code reçu après paiement (annuel ou à vie).",
      },
      { status: 400 },
    );
  }

  const apiUrl = activationApiUrl();
  const apiKey = activationApiKey();
  const adminSecret = activationAdminSecret();

  // Path A — same as admin-panel activateApi.activate → POST /api/v1/activate
  if (apiKey) {
    try {
      const upstream = await fetch(apiUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(panelActivateBody(mac, plan)),
      });
      return await mirrorUpstream(upstream, mac, plan);
    } catch {
      return NextResponse.json(
        {
          ok: false,
          message: "Impossible de joindre le service d'activation.",
        },
        { status: 502 },
      );
    }
  }

  // Path B — legacy Worker admin action (X-Admin-Secret), instant like panel buttons
  if (adminSecret) {
    try {
      const origin = workerOriginFromActivateUrl(apiUrl);
      const action = adminActionForPlan(plan);
      const upstream = await fetch(
        `${origin}/admin/clients/${encodeURIComponent(mac)}/action`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Admin-Secret": adminSecret,
          },
          body: JSON.stringify({ action }),
        },
      );
      return await mirrorUpstream(upstream, mac, plan);
    } catch {
      return NextResponse.json(
        {
          ok: false,
          message: "Impossible de joindre le service d'activation.",
        },
        { status: 502 },
      );
    }
  }

  return NextResponse.json(
    {
      ok: false,
      message:
        "Activation indisponible pour le moment. Contactez le support WhatsApp avec votre S code et votre M2.",
      mac,
      plan,
    },
    { status: 503 },
  );
}

async function mirrorUpstream(
  upstream: Response,
  mac: string,
  plan: PanelPlan,
) {
  const text = await upstream.text();
  let data: unknown = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }

  if (!upstream.ok) {
    const msg =
      (data as { message?: string; error?: string })?.message ||
      (data as { error?: string })?.error ||
      `Activation refusée (${upstream.status}).`;
    return NextResponse.json(
      {
        ok: false,
        message: String(msg),
        upstream: data,
      },
      {
        status:
          upstream.status >= 400 && upstream.status < 600
            ? upstream.status
            : 502,
      },
    );
  }

  return NextResponse.json({
    ok: true,
    stub: false,
    mac,
    plan,
    message: "Appareil activé.",
    upstream: data,
  });
}
