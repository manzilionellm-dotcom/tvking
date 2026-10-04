#!/usr/bin/env node
// Génère public/llms.txt depuis aio.config.json (source unique). Usage: node scripts/aio-llms.mjs
import fs from "node:fs";

const c = JSON.parse(fs.readFileSync(new URL("../aio.config.json", import.meta.url), "utf8"));
const L = c.defaultLang;
const i = c.i18n[L];
const lines = [];
const missing = "non indiqué";

lines.push(`# ${c.siteName}`, "", `> ${i.description}`, "");
lines.push("## Services", "");
for (const service of i.services) lines.push(`- ${service}`);
lines.push("", "## Prix", "");
for (const plan of c.plans) {
  const label = plan.priceLabel ?? (plan.price == null ? missing : `${plan.price} €`);
  const note = plan.note ? ` — ${plan.note}` : "";
  lines.push(`- ${plan.name[L]}: ${label}${note}`);
}
lines.push("", "## Caractéristiques techniques", "");
const tech = c.tech;
lines.push(`- Résolution maximale annoncée: ${tech.maxResolution ?? missing}`);
lines.push(`- Appareils: ${tech.devices?.length ? tech.devices.join(", ") : missing}`);
lines.push(`- Activation: ${tech.activationNote ?? tech.activationMinutes ?? missing}`);
lines.push(`- Débits / bande passante minimale: ${tech.bitrate ?? missing}`);
lines.push(`- Nombre de chaînes: ${tech.channelCount ?? missing}`);
if (tech.androidPackage) lines.push(`- Package Android indiqué: ${tech.androidPackage}`);
lines.push("", `## Questions fréquentes (${i.faq.length})`, "");
for (const item of i.faq) lines.push(`### ${item.q}`, "", item.a, "");

fs.mkdirSync(new URL("../public/", import.meta.url), { recursive: true });
fs.writeFileSync(new URL("../public/llms.txt", import.meta.url), lines.join("\n").trimEnd() + "\n");
console.log(`public/llms.txt écrit (${i.faq.length} Q/R)`);
