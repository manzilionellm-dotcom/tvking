import { NextResponse } from "next/server";
import { isValidMac, normalizeMac } from "../../lib/mac";

type Body = { mac?: string; code?: string; codes?: string[] };

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

  const macRaw = (body.mac || "").trim();
  const code =
    (body.code || "").trim() ||
    (Array.isArray(body.codes) ? body.codes.filter(Boolean).join(",") : "");

  if (!isValidMac(macRaw)) {
    return NextResponse.json(
      {
        ok: false,
        message: "Adresse MAC invalide. Format attendu : AA:BB:CC:DD:EE:FF",
      },
      { status: 400 },
    );
  }
  if (!code) {
    return NextResponse.json(
      { ok: false, message: "Code d'activation requis." },
      { status: 400 },
    );
  }

  const mac = normalizeMac(macRaw);
  const apiUrl = process.env.ACTIVATION_API_URL?.replace(/\/$/, "");
  const apiKey =
    process.env.ACTIVATION_API_KEY || process.env.ACTIVATION_API_TOKEN;

  if (!apiUrl) {
    return NextResponse.json({
      ok: true,
      stub: true,
      mac,
      message:
        "Demande validée localement (stub). Configurez ACTIVATION_API_URL pour activer réellement l'appareil.",
    });
  }

  try {
    const upstream = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
      },
      body: JSON.stringify({ mac, code, codes: code.split(/[,\s]+/).filter(Boolean) }),
    });
    const text = await upstream.text();
    let data: unknown = null;
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
    if (!upstream.ok) {
      return NextResponse.json(
        {
          ok: false,
          message:
            (data as { message?: string })?.message ||
            `Activation refusée (${upstream.status}).`,
          upstream: data,
        },
        { status: upstream.status >= 400 && upstream.status < 600 ? upstream.status : 502 },
      );
    }
    return NextResponse.json({
      ok: true,
      stub: false,
      mac,
      message: "Appareil activé avec succès.",
      upstream: data,
    });
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
