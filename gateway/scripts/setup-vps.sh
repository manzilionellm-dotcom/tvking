#!/usr/bin/env bash
# =========================================================
#  setup-vps.sh — Installation/mise à jour v500 + HTTPS de la passerelle
# =========================================================
#  À QUOI SERT CE SCRIPT (pour un débutant) :
#  Il prépare le fichier `.env` du gateway SUR LE VPS, en te demandant les
#  secrets DIRECTEMENT ici (saisie masquée), puis lance Docker (gateway +
#  Caddy = HTTPS automatique). Aucun secret n'est JAMAIS :
#    • affiché à l'écran pendant la saisie (saisie masquée, comme un mot de passe) ;
#    • écrit dans un log ou l'historique du shell ;
#    • passé en argument à une commande (donc invisible dans `ps`/`history`) ;
#    • enregistré dans Git (`.env` et `users.json` sont ignorés par `.gitignore`).
#
#  POURQUOI CE SCRIPT PLUTÔT QU'UN COPIER-COLLER À LA MAIN :
#  Le garde-fou n°1 du projet est « jamais de secret en clair dans un commit,
#  un doc ou un log ». Éditer `.env` à la main pousse à coller le mot de passe
#  quelque part. Ici, tu TAPES le secret dans une invite masquée : il va droit
#  dans `.env` (permissions 600, lisible par toi seul) et nulle part ailleurs.
#
#  UTILISATION (sur le VPS, dans le dossier du dépôt) :
#    cd gateway
#    bash scripts/setup-vps.sh
#
#  Le script est IDEMPOTENT : tu peux le relancer sans risque. Il met à jour
#  les clés existantes de `.env` sans écraser ce que tu ne changes pas.
# =========================================================
set -euo pipefail

# --- On se place dans le dossier `gateway/` (parent de `scripts/`) --------
# Ainsi le script marche que tu l'appelles depuis `gateway/` ou ailleurs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$GATEWAY_DIR"

ENV_FILE=".env"
ENV_EXAMPLE=".env.example"
USERS_FILE="users.json"
USERS_EXAMPLE="users.example.json"

# --- Petites fonctions d'affichage lisibles ------------------------------
info()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# =========================================================
#  Helpers `.env` — écriture SÛRE, en pur bash (aucun secret en argument)
# =========================================================
#  set_env : met à jour la clé si elle existe, l'ajoute sinon. La VALEUR n'est
#  jamais passée à `sed`/`awk` (qui l'exposeraient dans `ps`) : on réécrit le
#  fichier ligne par ligne avec `printf`, la valeur restant dans une variable.
set_env() {
  local key="$1" val="$2" tmp found=0 line
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$val" >>"$tmp"
        found=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$ENV_FILE"
  fi
  [ "$found" -eq 0 ] && printf '%s=%s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

# get_env : lit la valeur actuelle d'une clé (ou vide). Sert à NE PAS écraser
# un secret déjà en place et à détecter les valeurs-exemple à remplacer.
get_env() {
  [ -f "$ENV_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "$1="* ]]; then printf '%s' "${line#*=}"; return 0; fi
  done <"$ENV_FILE"
}

# gen_secret : génère un secret fort (24 caractères alphanumériques). On retire
# / + = pour éviter tout souci d'échappement dans une URL ou un fichier .env.
gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-24
  else
    # Repli sans openssl : source d'aléa du noyau.
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
  fi
}

# ask_secret : invite MASQUÉE (le secret ne s'affiche pas). Si l'utilisateur
# laisse vide et qu'une valeur existe déjà, on garde l'existante.
# $1=libellé  $2=nom_variable_retour  $3=valeur_actuelle (optionnel)
ask_secret() {
  local label="$1" __ret="$2" current="${3:-}" input
  if [ -n "$current" ]; then
    printf '   %s [garder la valeur actuelle : Entrée] : ' "$label"
  else
    printf '   %s : ' "$label"
  fi
  read -rs input; echo
  if [ -z "$input" ] && [ -n "$current" ]; then
    printf -v "$__ret" '%s' "$current"
  else
    printf -v "$__ret" '%s' "$input"
  fi
}

# ask_plain : invite normale (valeur non sensible) avec valeur par défaut.
ask_plain() {
  local label="$1" __ret="$2" def="${3:-}" input
  if [ -n "$def" ]; then printf '   %s [%s] : ' "$label" "$def"
  else printf '   %s : ' "$label"; fi
  read -r input
  printf -v "$__ret" '%s' "${input:-$def}"
}

# =========================================================
#  0) Pré-requis
# =========================================================
info "Vérification des pré-requis (docker, docker compose)…"
command -v docker >/dev/null 2>&1 || die "Docker n'est pas installé. Installe Docker d'abord."
# Détecte `docker compose` (v2, recommandé) ou `docker-compose` (v1).
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  die "docker compose introuvable. Installe le plugin Compose."
fi
ok "Docker et Compose détectés ($COMPOSE)."

# =========================================================
#  1) Fichier .env — création depuis l'exemple si absent
# =========================================================
if [ ! -f "$ENV_FILE" ]; then
  [ -f "$ENV_EXAMPLE" ] || die "$ENV_EXAMPLE introuvable — es-tu bien dans gateway/ ?"
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok ".env créé depuis .env.example (permissions 600)."
else
  chmod 600 "$ENV_FILE"
  ok ".env déjà présent (permissions resserrées à 600)."
fi

echo
info "=== Configuration de la passerelle (v500 + HTTPS) ==="
echo "  Astuce : laisse vide pour conserver une valeur déjà en place."
echo

# =========================================================
#  2) Domaine + URLs publiques (HTTPS)
# =========================================================
CUR_DOMAIN="$(get_env DOMAIN || true)"
# Si la valeur actuelle est l'exemple, on propose le domaine cible du projet.
case "$CUR_DOMAIN" in ""|"tv.mondomaine.com") CUR_DOMAIN="gw.7themotion.com";; esac
ask_plain "Domaine public (A DNS → IP du VPS, nuage GRIS)" DOMAIN "$CUR_DOMAIN"
[ -n "$DOMAIN" ] || die "Le domaine est obligatoire pour le certificat HTTPS."
set_env DOMAIN "$DOMAIN"
# PUBLIC_BASE DOIT être en https:// et sans slash final : c'est l'URL que les
# apps et le Worker joignent, et celle réécrite dans les playlists M3U.
set_env PUBLIC_BASE "https://$DOMAIN"
ok "DOMAIN=$DOMAIN · PUBLIC_BASE=https://$DOMAIN"

# =========================================================
#  3) Ligne fournisseur (UPSTREAM_*) — UNE seule ligne réelle
# =========================================================
echo
info "Ligne fournisseur (la SEULE ligne réelle ; elle reste cachée derrière la façade)."
CUR_UP_BASE="$(get_env UPSTREAM_BASE || true)"
case "$CUR_UP_BASE" in "http://mon-fournisseur.com:8080") CUR_UP_BASE="";; esac
ask_plain "URL fournisseur (ex. http://serveur.tld:8080)" UP_BASE "$CUR_UP_BASE"
[ -n "$UP_BASE" ] && set_env UPSTREAM_BASE "$UP_BASE"

CUR_UP_USER="$(get_env UPSTREAM_USER || true)"
case "$CUR_UP_USER" in "ma_ligne_user") CUR_UP_USER="";; esac
ask_plain "Utilisateur fournisseur" UP_USER "$CUR_UP_USER"
[ -n "$UP_USER" ] && set_env UPSTREAM_USER "$UP_USER"

# Le mot de passe fournisseur est un SECRET → saisie masquée.
UP_PASS=""
ask_secret "Mot de passe fournisseur (secret, masqué)" UP_PASS "$(get_env UPSTREAM_PASS || true)"
[ -n "$UP_PASS" ] && set_env UPSTREAM_PASS "$UP_PASS"
unset UP_PASS  # on ne garde pas le secret en mémoire du script plus que nécessaire

# Plafond anti-ban : jamais plus de connexions que la ligne n'en autorise.
CUR_MAX="$(get_env PROVIDER_MAX_CONNECTIONS || true)"; [ -n "$CUR_MAX" ] || CUR_MAX="5"
ask_plain "Connexions max autorisées par le fournisseur" PMAX "$CUR_MAX"
set_env PROVIDER_MAX_CONNECTIONS "$PMAX"
ok "Ligne fournisseur enregistrée (mot de passe masqué)."

# =========================================================
#  4) Identité de DIFFUSION — l'utilisateur partagé des tests
# =========================================================
#  C'est CETTE identité que le panel embarque dans les URLs de la liste de
#  test, À LA PLACE des identifiants fournisseur → la vraie ligne n'apparaît
#  jamais dans le M3U servi. Le mot de passe doit être fort ET identique à
#  celui saisi dans la console maître (champ « mot de passe gateway »).
echo
info "Identité de diffusion (utilisateur partagé des tests)."
set_env BROADCAST_USER "diffusion"

CUR_BPASS="$(get_env BROADCAST_PASS || true)"
case "$CUR_BPASS" in ""|"change-moi-un-secret-diffusion") CUR_BPASS="";; esac
BROADCAST_PASS=""
if [ -n "$CUR_BPASS" ]; then
  ask_secret "Mot de passe diffusion (Entrée = garder l'actuel)" BROADCAST_PASS "$CUR_BPASS"
else
  echo "   Aucun mot de passe de diffusion valide en place."
  ask_plain "   Générer un mot de passe fort automatiquement ? (o/n)" GEN "o"
  if [[ "$GEN" =~ ^[oOyY] ]]; then
    BROADCAST_PASS="$(gen_secret)"
    GENERATED_BPASS=1
  else
    ask_secret "Mot de passe diffusion (secret, masqué)" BROADCAST_PASS ""
  fi
fi
[ -n "$BROADCAST_PASS" ] || die "Un mot de passe de diffusion est requis."
set_env BROADCAST_PASS "$BROADCAST_PASS"

CUR_BMAX="$(get_env BROADCAST_MAX_STREAMS || true)"; [ -n "$CUR_BMAX" ] || CUR_BMAX="100"
set_env BROADCAST_MAX_STREAMS "$CUR_BMAX"
ok "Identité de diffusion : diffusion / (mot de passe masqué) · max $CUR_BMAX testeurs."

# =========================================================
#  5) Jeton admin (/admin/*, /metrics) — généré si encore à l'exemple
# =========================================================
CUR_ADMIN="$(get_env ADMIN_TOKEN || true)"
case "$CUR_ADMIN" in ""|"change-moi-un-long-secret")
  set_env ADMIN_TOKEN "$(gen_secret)$(gen_secret)"
  ok "ADMIN_TOKEN généré automatiquement (secret, resté dans .env)."
  ;;
*) ok "ADMIN_TOKEN déjà personnalisé — conservé.";;
esac

# =========================================================
#  6) users.json — familles/clones (créé depuis l'exemple si absent)
# =========================================================
if [ ! -f "$USERS_FILE" ]; then
  if [ -f "$USERS_EXAMPLE" ]; then
    cp "$USERS_EXAMPLE" "$USERS_FILE"
    warn "users.json créé depuis l'exemple — PENSE à changer les mots de passe des clones."
  else
    printf '{ "families": [] }\n' >"$USERS_FILE"
    ok "users.json minimal créé (aucune famille ; l'identité de diffusion vient du .env)."
  fi
  chmod 600 "$USERS_FILE"
else
  ok "users.json déjà présent — conservé."
fi

# =========================================================
#  7) Lancement Docker (gateway + Caddy = HTTPS auto)
# =========================================================
echo
info "Lancement des conteneurs (build + up)…"
info "Caddy va demander un certificat Let's Encrypt pour $DOMAIN (ports 80+443)."
warn "Pré-requis DNS : un enregistrement A '$DOMAIN' → IP du VPS, NUAGE GRIS (DNS only)."
$COMPOSE up -d --build
ok "Conteneurs démarrés."

# =========================================================
#  8) Vérification santé HTTPS (preuve de bout en bout)
# =========================================================
echo
info "Vérification de https://$DOMAIN/health (le certificat peut prendre ~30 s)…"
HEALTH_OK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 8 "https://$DOMAIN/health" >/tmp/gw_health.json 2>/dev/null; then
    HEALTH_OK=1
    break
  fi
  sleep 6
done

echo
if [ "$HEALTH_OK" -eq 1 ]; then
  ok "https://$DOMAIN/health répond :"
  cat /tmp/gw_health.json; echo
  ok "PASSERELLE EN LIGNE EN HTTPS (v500). Diagnostic sondable → prêt pour le VERT."
else
  warn "Pas encore de réponse HTTPS. Causes fréquentes :"
  echo "   • DNS pas encore propagé (attends quelques minutes, revérifie)."
  echo "   • Le nuage DNS n'est PAS gris (proxy Cloudflare actif) → Caddy ne peut"
  echo "     pas obtenir le certificat. Repasse l'enregistrement A en 'DNS only'."
  echo "   • Ports 80/443 fermés par le pare-feu du VPS/hébergeur → ouvre-les."
  echo "   Logs utiles :  $COMPOSE logs --tail=50 caddy"
fi

# =========================================================
#  9) Rappel du mot de passe de diffusion à reporter dans le PANEL
# =========================================================
#  Le panel a besoin du MÊME mot de passe de diffusion (champ « mot de passe
#  gateway »). On l'affiche UNE fois ici, sur TON terminal (jamais dans un log
#  ni un commit), seulement s'il vient d'être généré par le script.
if [ "${GENERATED_BPASS:-0}" = "1" ]; then
  echo
  warn "=== À REPORTER DANS LE PANEL, PUIS À OUBLIER (affiché une seule fois) ==="
  echo "   Façade (gateway)        : https://$DOMAIN"
  echo "   Utilisateur de diffusion: diffusion"
  printf '   Mot de passe diffusion  : %s\n' "$BROADCAST_PASS"
  echo "   (Ce secret est déjà dans .env côté serveur. Ne le colle NULLE PART"
  echo "    ailleurs — ni commit, ni doc, ni message.)"
fi
unset BROADCAST_PASS

echo
ok "Terminé. Prochaine étape : configure la façade dans le panel puis lance le Diagnostic."
