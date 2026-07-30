# =========================================================
#  Edge proxy — image de déploiement
# =========================================================
#  Le service n'a AUCUNE dépendance npm : il n'importe que des modules
#  natifs de Node (node:http, node:sqlite, node:fs…). L'image se réduit
#  donc au runtime plus les sources — pas de `npm install`, pas d'étape
#  de build, rien à recompiler à chaque déploiement.
#
#  Node 22 exécute le TypeScript directement (type stripping), d'où
#  `node main.ts` sans transpilation. `node:sqlite` y est marqué
#  expérimental : il fonctionne sans drapeau, il émet juste un
#  avertissement au démarrage — attendu, pas une erreur.
#
#  Contexte de build = ce dossier :
#      docker build -t tvking-edge server/edge
# =========================================================
FROM node:22-alpine

# Le service tourne en non-root. Les deux volumes (base et médias) lui
# appartiennent : sans ça, un `docker run` sur un hôte Linux écrit des
# fichiers root dans les dossiers montés.
WORKDIR /app
COPY --chown=node:node . /app/

# Emplacements par défaut, tous deux prévus pour être montés en volume.
# Les laisser dans /data évite le piège classique du stockage écrit dans
# la couche image (perdu à chaque redéploiement).
ENV EDGE_DB=/data/edge.db \
    EDGE_VOD_DIR=/data/vod \
    EDGE_HOST=0.0.0.0 \
    EDGE_PORT=8787 \
    NODE_ENV=production
RUN mkdir -p /data/vod && chown -R node:node /data
VOLUME ["/data"]
USER node

EXPOSE 8787

# Sonde de vie : le plan d'administration exige un jeton, et la racine du
# préfixe de flux répond sans authentification — on interroge donc le
# port lui-même. Un 404 prouve que le processus écoute et route.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null --spider "http://127.0.0.1:${EDGE_PORT}/" 2>/dev/null || \
      [ "$(wget -qS -O /dev/null "http://127.0.0.1:${EDGE_PORT}/" 2>&1 | grep -c 'HTTP/')" -gt 0 ]

CMD ["node", "main.ts"]
