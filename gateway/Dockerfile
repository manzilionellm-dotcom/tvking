# ============================================================================
# Dockerfile — Gateway 7 MOTION
#
# Image minimale : Node LTS « slim », aucune dépendance npm (le gateway n'utilise
# que les modules natifs de Node). Tourne en utilisateur non-root.
# ============================================================================
FROM node:22-slim

# Répertoire de travail applicatif.
WORKDIR /app

# On copie d'abord le manifeste (cache Docker), puis le code source.
# Aucune dépendance externe → pas de `npm install` nécessaire.
COPY package.json ./
COPY src ./src
COPY test ./test

# L'utilisateur « node » existe déjà dans l'image officielle ; on l'utilise pour
# ne pas tourner en root.
USER node

# Port HTTP interne (Caddy proxifie ici en TLS). Ajustable via PORT.
EXPOSE 8088

# Vérification de santé : le gateway expose /healthz.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||8088)+'/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# Démarrage du gateway.
CMD ["node", "src/index.js"]
