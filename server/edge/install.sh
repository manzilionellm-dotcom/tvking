#!/usr/bin/env bash
# =========================================================
#  install.sh — Installe le Cinéma / VOD sur TON serveur
# =========================================================
#  Une seule commande. Le script :
#    1. vérifie que Docker est là ;
#    2. GÉNÈRE le mot de passe du tableau de bord (rien à inventer) ;
#    3. demande ton lien M3U / Xtream ;
#    4. écrit .env, construit l'image et démarre le service ;
#    5. affiche l'adresse du tableau de bord et le mot de passe.
#
#  Usage :
#      cd server/edge && ./install.sh
#
#  Options :
#      --no-start   prépare .env sans construire ni démarrer (test à blanc)
#      --port N     écoute sur le port N au lieu de 8787
#
#  Relancer le script est sans danger : un .env existant n'est JAMAIS
#  écrasé (tes identifiants et ton mot de passe survivent aux mises à
#  jour). Pour repartir de zéro, supprime .env à la main.
# =========================================================
set -euo pipefail

cd "$(dirname "$0")"

PORT=8787
START=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-start) START=0; shift ;;
    --port) PORT="${2:?--port attend un numéro}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "option inconnue : $1 (essaie --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. Docker -----------------------------------------------------------
if [ "$START" = 1 ]; then
  command -v docker >/dev/null 2>&1 \
    || die "Docker n'est pas installé. Sur Debian/Ubuntu :
    curl -fsSL https://get.docker.com | sh"
  docker info >/dev/null 2>&1 \
    || die "Docker est installé mais ne répond pas.
    Démarre-le (sudo systemctl start docker) ou relance avec sudo."
  docker compose version >/dev/null 2>&1 \
    || die "Il manque le plugin « docker compose » (Docker trop ancien).
    Voir https://docs.docker.com/compose/install/"
fi

# --- 2. Configuration ----------------------------------------------------
if [ -f .env ]; then
  say "Un fichier .env existe déjà — je le garde tel quel."
  warn "Tes identifiants et ton mot de passe sont conservés."
  warn "Pour tout refaire : supprime .env puis relance ce script."
else
  # Mot de passe du tableau de bord : généré, jamais choisi par un humain
  # (un mot de passe tapé à la main sur une API qui peut repointer le
  # proxy, c'est le maillon faible garanti).
  if command -v openssl >/dev/null 2>&1; then
    TOKEN="$(openssl rand -hex 32)"
  else
    TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  [ -n "$TOKEN" ] || die "Impossible de générer un mot de passe (ni openssl ni /dev/urandom)."

  say "Colle ton lien M3U ou Xtream (celui de ton fournisseur)"
  echo "  exemple : http://serveur.tv/get.php?username=xxx&password=yyy&type=m3u_plus"
  printf '> '
  read -r PLAYLIST_URL
  case "$PLAYLIST_URL" in
    http://*|https://*) ;;
    *) die "Ce n'est pas une URL. Elle doit commencer par http:// ou https://" ;;
  esac

  # Écrit AVANT de démarrer : si le démarrage échoue, la configuration
  # est déjà sur le disque et il n'y a rien à retaper.
  umask 077   # .env porte des identifiants IPTV : lisible par toi seul.
  # Le JSON est entre apostrophes : Docker Compose retire les apostrophes
  # encadrantes, et un `source .env` en shell préserve les guillemets
  # intérieurs. Sans elles, le shell les mange et le JSON devient invalide.
  cat > .env <<EOF
# Généré par install.sh — modifiable à la main, puis :
#     docker compose up -d --force-recreate
EDGE_ACCOUNTS='[{"id":"master","label":"Ligne principale","playlistUrl":"${PLAYLIST_URL}","maxConnections":1,"device":"vlc"}]'
EDGE_ADMIN_TOKEN=${TOKEN}
EDGE_DB=/data/edge.db
EDGE_VOD_DIR=/data/vod
EDGE_VOD=1
EDGE_PORTAL=1
EDGE_HOST=0.0.0.0
EDGE_PORT=8787
EOF
  say "Configuration écrite dans .env"
fi

# Le port publié vit dans compose, pas dans .env : on le passe par
# l'environnement plutôt que de réécrire le fichier de l'utilisateur.
export EDGE_PUBLISHED_PORT="$PORT"

if [ "$START" = 0 ]; then
  say "Test à blanc terminé — rien n'a été construit ni démarré."
  exit 0
fi

# --- 3. Démarrage --------------------------------------------------------
say "Construction de l'image (une minute la première fois)…"
docker compose build

say "Démarrage…"
docker compose up -d

# Laisse au service le temps d'ouvrir son port avant de conclure.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  if docker compose ps --status running --quiet 2>/dev/null | grep -q .; then break; fi
done

TOKEN_NOW="$(grep -E '^EDGE_ADMIN_TOKEN=' .env | cut -d= -f2-)"

say "C'est en ligne."
cat <<EOF

  Tableau de bord : http://127.0.0.1:${PORT}/admin/
  Mot de passe    : ${TOKEN_NOW}

  Onglet « Cinéma / VOD » → « Ajouter une source » → « Télécharger ».

EOF
warn "Le port n'est ouvert que sur cette machine (127.0.0.1)."
warn "Depuis ton PC :  ssh -L ${PORT}:127.0.0.1:${PORT} <user>@<serveur>"
warn "puis ouvre http://127.0.0.1:${PORT}/admin/ dans ton navigateur."
echo
echo "  Journal  : docker compose logs -f"
echo "  Arrêter  : docker compose down"
echo "  Sauvegarde : le volume Docker « edge-data » contient TOUT."
echo
