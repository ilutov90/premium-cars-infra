#!/bin/sh
# Run on the production server (as deploy) by scripts/local-worker.ps1 on an admin's laptop: prints, as KEY=value
# lines, what that laptop's backend needs to run the automatic import against this database (docs/local-worker.md):
# the PostgreSQL and Vault container addresses (for the SSH tunnel), the backend's AppRole login (read-only on the
# backend's secrets) and its non-secret settings, and whether production's own import is off. Changes nothing.
set -eu

container() {
  docker ps -q -f label=com.docker.compose.project=premium-cars-prod -f "label=com.docker.compose.service=$1" \
    | head -n 1
}
address() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

backend=$(container backend)
postgres=$(container postgres)
vault=$(container vault)
if [ -z "$backend" ] || [ -z "$postgres" ] || [ -z "$vault" ]; then
  echo "ERROR=production is not running (backend, postgres or vault missing)"
  exit 1
fi

echo "PG_IP=$(address "$postgres")"
echo "VAULT_IP=$(address "$vault")"
# shellcheck disable=SC2016 # expanded inside the container
docker exec "$backend" sh -c '
  echo "PROD_AUTO_IMPORT=${APP_AUTO_IMPORT_ENABLED:-true}"
  echo "R2_ENDPOINT=${R2_ENDPOINT:-}"
  echo "R2_BUCKET=${R2_BUCKET:-}"
  echo "R2_PUBLIC_URL=${R2_PUBLIC_URL:-}"
  echo "APP_SITE_URL=${APP_SITE_URL:-}"
  echo "APP_NOTIFY_TO=${APP_NOTIFY_TO:-}"
  echo "APP_NOTIFY_FROM=${APP_NOTIFY_FROM:-}"
  sed -n "s/^spring\.cloud\.vault\.app-role\.role-id=/ROLE_ID=/p; s/^spring\.cloud\.vault\.app-role\.secret-id=/SECRET_ID=/p" \
    /run/vault/backend-approle.properties'
