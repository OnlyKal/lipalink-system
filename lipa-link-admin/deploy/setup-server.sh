#!/usr/bin/env bash
# Préparation du serveur (Ubuntu/Debian), à exécuter en root SUR le serveur.
# Idempotent : peut être relancé à chaque déploiement sans rien casser.
# N'ajoute qu'un site nginx dédié ; les autres sites ne sont pas touchés.
set -euo pipefail

DOMAIN="${DOMAIN:-lipalink.liviatech.store}"
APP_DIR="${APP_DIR:-/opt/lipalink-admin}"
PORT="${PORT:-4180}"
ENV_FILE=/etc/lipalink-admin.env
SERVICE=lipalink-admin
# Le port déjà configuré sur le serveur fait foi (nginx et service d'accord).
if [ -f "$ENV_FILE" ] && grep -q '^PORT=' "$ENV_FILE"; then
  PORT=$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)
fi

log() { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- Paquets
need_apt=()
command -v nginx >/dev/null || need_apt+=(nginx)
command -v certbot >/dev/null || need_apt+=(certbot python3-certbot-nginx)
command -v make >/dev/null || need_apt+=(build-essential)   # better-sqlite3 si pas de binaire précompilé
command -v rsync >/dev/null || need_apt+=(rsync)
if ((${#need_apt[@]})); then
  log "Installation : ${need_apt[*]}"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need_apt[@]}"
fi

node_major=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/' || echo 0)
if [ "${node_major:-0}" -lt 18 ]; then
  log "Installation de Node.js 20"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi
log "Node $(node -v)"

# ------------------------------------------------------ Utilisateur & données
id lipalink >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin lipalink
mkdir -p "$APP_DIR/data"
chown -R lipalink:lipalink "$APP_DIR/data"

# ---------------------------------------------------------- Configuration
if [ ! -f "$ENV_FILE" ]; then
  log "Création de $ENV_FILE (mot de passe admin généré)"
  ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)
  cat >"$ENV_FILE" <<EOF
NODE_ENV=production
PORT=$PORT
HOST=127.0.0.1
DATA_DIR=$APP_DIR/data
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF
  chmod 600 "$ENV_FILE"
  echo "$ADMIN_PASSWORD" >/root/lipalink-admin-password.txt
  chmod 600 /root/lipalink-admin-password.txt
fi

# Le port doit être libre (ou déjà utilisé par notre propre service).
if ss -tln "sport = :$PORT" | grep -q LISTEN && ! systemctl is-active --quiet "$SERVICE"; then
  echo "✖ Le port $PORT est déjà utilisé sur ce serveur. Changez PORT dans $ENV_FILE." >&2
  exit 1
fi

# ---------------------------------------------------------------- Service
cat >/etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=LipaLink Cloud (administration et sauvegardes)
After=network.target

[Service]
Type=simple
User=lipalink
WorkingDirectory=$APP_DIR/server
EnvironmentFile=$ENV_FILE
ExecStart=$(command -v node) src/index.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=$APP_DIR/data

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --quiet $SERVICE

# ------------------------------------------------------------------ nginx
SITE=/etc/nginx/sites-available/$DOMAIN
if [ ! -f "$SITE" ]; then
  log "Site nginx $DOMAIN"
  cat >"$SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size 30m;   # sauvegardes envoyées par les téléphones

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF
  ln -sf "$SITE" /etc/nginx/sites-enabled/$DOMAIN
  nginx -t
  systemctl reload nginx
fi

# ------------------------------------------------------------------ HTTPS
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  log "Certificat HTTPS Let's Encrypt"
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
fi

log "Serveur prêt"
