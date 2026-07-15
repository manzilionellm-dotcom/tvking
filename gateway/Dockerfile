# =========================================================
#  Dockerfile — Passerelle IPTV « maison mère »
# =========================================================
FROM node:20-alpine

# Bonnes pratiques : app non-root, dossier /data pour users.json.
WORKDIR /app

# Dépendances d'abord (cache Docker).
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

# Code
COPY src ./src

# Données (users.json monté en volume)
RUN mkdir -p /data && chown -R node:node /app /data
USER node

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8088

EXPOSE 8088

# Healthcheck interne
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8088/health >/dev/null 2>&1 || exit 1

CMD ["node", "src/index.js"]
