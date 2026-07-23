'use strict';

/**
 * index.js — Point d'entrée du gateway 7 MOTION.
 *
 * Charge la configuration (env / .env via docker-compose), démarre le serveur
 * HTTP, journalise l'état de capacité, et gère l'arrêt propre (SIGTERM/SIGINT)
 * pour ne pas laisser de connexion fournisseur pendante.
 */

const { loadConfig } = require('./config');
const { createServer } = require('./server');
const { makeLogger } = require('./hub');

function main() {
  // requireUpstream: true → refuse de démarrer sans UPSTREAM_BASE / identité diffusion.
  const cfg = loadConfig(process.env, { requireUpstream: true });
  const log = makeLogger(cfg.LOG_LEVEL);

  const { server, hub } = createServer(cfg, { logger: log });

  server.listen(cfg.PORT, cfg.HOST, () => {
    log.info('──────────────────────────────────────────────────────────');
    log.info('Gateway 7 MOTION démarré');
    log.info(`  Écoute            : http://${cfg.HOST}:${cfg.PORT}`);
    log.info(`  Façade publique   : ${cfg.PUBLIC_BASE || '(non définie)'}`);
    log.info(`  Amont             : ${cfg.UPSTREAM_BASE || '(non défini)'}`);
    log.info(`  Connexions amont  : ${cfg.PROVIDER_MAX_CONNECTIONS} max (limite ligne)`);
    log.info(`  Spectateurs max   : ${cfg.BROADCAST_MAX_STREAMS}`);
    log.info(
      `  Tampon/ client    : ${(cfg.CLIENT_BUFFER_MAX_BYTES / 1024 / 1024).toFixed(0)} Mo`,
    );
    log.info(
      `  Tampon global     : ${(cfg.GLOBAL_CLIENT_BUFFER_MAX_BYTES / 1024 / 1024).toFixed(0)} Mo`,
    );
    log.info('──────────────────────────────────────────────────────────');
  });

  // Erreurs serveur (ex. port occupé).
  server.on('error', (err) => {
    log.error(`Erreur serveur : ${err.message}`);
    process.exit(1);
  });

  // Arrêt propre : on ferme le hub (donc les connexions amont) puis le serveur.
  const shutdown = (sig) => {
    log.info(`Signal ${sig} reçu — arrêt propre…`);
    hub.close();
    server.close(() => {
      log.info('Serveur fermé. Au revoir.');
      process.exit(0);
    });
    // Filet de sécurité : on force la sortie si des sockets traînent.
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(`[fatal] ${err.message}`);
    process.exit(1);
  }
}

module.exports = { main };
