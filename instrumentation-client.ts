/*
 * Exécuté avant que l'application ne devienne interactive (convention Next
 * instrumentation-client) — c'est ici que les polyfills pour les WebView
 * anciens des box TV doivent se charger, avant tout code applicatif.
 */
import "./app/lib/polyfills";
