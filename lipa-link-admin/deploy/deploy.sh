#!/usr/bin/env bash
# Déploiement complet depuis ton ordinateur :
#   ./deploy/deploy.sh
# Compile le dashboard, envoie le code, prépare le serveur (1re fois),
# installe les dépendances et redémarre le service.
set -euo pipefail

REMOTE="${REMOTE:-root@194.34.232.102}"
APP_DIR="${APP_DIR:-/opt/lipalink-admin}"
DOMAIN="${DOMAIN:-lipalink.liviatech.store}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_lipalink}"
SSH="ssh -i $SSH_KEY -o IdentitiesOnly=yes"

cd "$(dirname "$0")/.."
log() { printf '\n\033[1;32m▸ %s\033[0m\n' "$*"; }

log "Compilation du dashboard"
(cd web && npm ci --silent && npm run build --silent)

log "Envoi des fichiers vers $REMOTE:$APP_DIR"
$SSH "$REMOTE" "mkdir -p $APP_DIR/server $APP_DIR/web/dist $APP_DIR/deploy"
# --delete ne touche pas aux exclusions : node_modules et data sont préservés.
rsync -az -e "$SSH" --delete --exclude node_modules --exclude data --exclude .DS_Store server/ "$REMOTE:$APP_DIR/server/"
rsync -az -e "$SSH" --delete web/dist/ "$REMOTE:$APP_DIR/web/dist/"
rsync -az -e "$SSH" deploy/ "$REMOTE:$APP_DIR/deploy/"

log "Préparation du serveur et redémarrage"
$SSH "$REMOTE" "set -e
  DOMAIN=$DOMAIN APP_DIR=$APP_DIR bash $APP_DIR/deploy/setup-server.sh
  cd $APP_DIR/server && npm ci --omit=dev --silent
  systemctl restart lipalink-admin
  sleep 2
  systemctl is-active lipalink-admin
  curl -fsS http://127.0.0.1:\$(grep ^PORT= /etc/lipalink-admin.env | cut -d= -f2)/api/health"

log "Vérification publique"
curl -fsS "https://$DOMAIN/api/health" && echo
echo "Dashboard : https://$DOMAIN"
echo "Mot de passe admin : $SSH $REMOTE cat /root/lipalink-admin-password.txt"
