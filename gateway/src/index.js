// =========================================================
//  index.js — Point d'entrée de la passerelle « maison mère »
// =========================================================
import { config, validateConfig } from './config.js';
import { log } from './logger.js';
import { loadUsers } from './users.js';
import { hub } from './hub.js';
import { createServer } from './server.js';

async function main() {
  const missing = validateConfig();
  if (missing.length) {
    log.error('config.invalid', { missing });
    // eslint-disable-next-line no-process-exit
    process.exit(1);
  }

  await loadUsers();

  const server = createServer();
  server.listen(config.port, config.host, () => {
    log.info('gateway.listening', {
      host: config.host,
      port: config.port,
      upstream: config.upstreamBase,
      providerMax: config.providerMaxConnections,
      publicBase: config.publicBase || '(non défini)',
    });
  });

  // Arrêt propre : on ferme tous les flux upstream (libère la ligne).
  let shuttingDown = false;
  const shutdown = (sig) => {
    if (shuttingDown) return;
    shuttingDown = true;
    log.info('gateway.shutdown', { signal: sig });
    hub.closeAll();
    server.close(() => process.exit(0));
    // Filet de sécurité si des sockets traînent.
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((e) => {
  log.error('gateway.fatal', { error: String(e && e.stack || e) });
  process.exit(1);
});
