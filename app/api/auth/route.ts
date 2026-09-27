import { NextResponse } from "next/server";

/** Demo auth stub — replace with Auth.js / Clerk later. */
export async function POST(req: Request) {
  let body: { email?: string; password?: string; mode?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, message: "JSON invalide." }, { status: 400 });
  }
  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";
  if (!email || !email.includes("@")) {
    return NextResponse.json({ ok: false, message: "E-mail invalide." }, { status: 400 });
  }
  if (password.length < 4) {
    return NextResponse.json(
      { ok: false, message: "Mot de passe trop court (min. 4)." },
      { status: 400 },
    );
  }
  return NextResponse.json({
    ok: true,
    stub: true,
    mode: body.mode === "register" ? "register" : "login",
    email,
    message:
      body.mode === "register"
        ? "Compte démo créé (stub). Session locale uniquement."
        : "Connexion démo réussie (stub).",
  });
}
