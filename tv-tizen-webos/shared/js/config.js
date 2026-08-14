// =========================================================
//  config.js — Configuration globale de DeFew TV (Tizen / webOS)
// =========================================================
//  App web pour Samsung (Tizen) et LG (webOS). MÊME backend que les apps
//  Android (app.7themotion.com) : activation par MAC, source poussée par le
//  panel, statut d'abonnement. Aucune URL IPTV en dur (règle AGENTS.md).
// =========================================================
window.DFT = window.DFT || {};

DFT.config = {
  // Backend Cloudflare — IDENTIQUE aux apps mobiles/TV Android.
  apiBase: 'https://app.7themotion.com',
  appName: 'The Few',
  // Extension des flux Xtream Live. La plupart des serveurs servent du MPEG-TS
  // (.ts) ; certains préfèrent le HLS (.m3u8). Si l'image ne démarre pas,
  // basculer ici. AVPlay (Samsung) lit les deux ; webOS lit le HLS nativement.
  streamExt: 'm3u8',
  // Délais réseau (ms).
  httpTimeout: 12000,
};
