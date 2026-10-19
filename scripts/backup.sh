#!/bin/sh
# Nightly backup of production (systemd/premium-cars-backup.timer runs it as root):
#   the database (pg_dump), the car photos, Vault's data and its unseal key + AppRole file
#   -> encrypted with restic -> Cloudflare R2 (any S3 storage works).
# Keeps 7 daily, 4 weekly and 6 monthly snapshots.
#
# Settings in /etc/premium-cars/backup.env (root only, chmod 600), see backup.env.example:
#   RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# The restic password must ALSO be in Bitwarden: without it the backups cannot be read.
#
#   sudo ./scripts/backup.sh            back up now
#   sudo ./scripts/backup.sh snapshots  list the backups
set -eu
cd "$(dirname "$0")/.."
ENV_FILE=${BACKUP_ENV:-/etc/premium-cars/backup.env}
RESTIC_IMAGE=restic/restic:0.18.0
PROJECT=premium-cars-prod
DUMP_DIR=/var/backups/premium-cars
SECRETS_DIR=$(pwd)/vault/secrets-prod

[ -r "$ENV_FILE" ] || { echo "missing $ENV_FILE (see scripts/backup.env.example)"; exit 1; }

restic() {
  docker run --rm --env-file "$ENV_FILE" --hostname premium-cars \
    -v "$DUMP_DIR":/backup/database:ro \
    -v "${PROJECT}_media":/backup/media:ro \
    -v "${PROJECT}_vaultdata":/backup/vault-data:ro \
    -v "$SECRETS_DIR":/backup/vault-secrets:ro \
    -v premium-cars-restic-cache:/root/.cache/restic \
    "$RESTIC_IMAGE" "$@"
}

if [ "${1:-}" = "snapshots" ]; then
  restic snapshots
  exit 0
fi

echo "$(date -Is) database dump"
mkdir -p "$DUMP_DIR"
chmod 700 "$DUMP_DIR"
./scripts/prod.sh exec -T postgres pg_dump -U postgres -Fc premiumcars > "$DUMP_DIR/premiumcars.dump.tmp"
mv "$DUMP_DIR/premiumcars.dump.tmp" "$DUMP_DIR/premiumcars.dump"

restic cat config >/dev/null 2>&1 || { echo "$(date -Is) creating the restic repository"; restic init; }

echo "$(date -Is) backup"
restic backup /backup --tag nightly
echo "$(date -Is) removing old snapshots"
restic forget --tag nightly --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
echo "$(date -Is) done"
