# Node + ffmpeg (remux -c copy, pas de re-encodage -> image legere suffit).
FROM node:20-alpine

RUN apk add --no-cache ffmpeg

WORKDIR /app
COPY server.js ./

ENV PORT=8080
EXPOSE 8080

# Pas de dependances npm : server.js n'utilise que la lib standard Node.
CMD ["node", "server.js"]
