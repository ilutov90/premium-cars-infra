#!/bin/sh
# Proves the backups can be read: restores the newest database dump into a throwaway PostgreSQL and counts the
# cars and inquiries. Production is not touched. Run every few months:  sudo ./scripts/restore-test.sh
#
# A real restore (new server) is in README "Production" -> "Restore from a backup".
set -eu
cd "$(dirname "$0")/.."
ENV_FILE=${BACKUP_ENV:-/etc/premium-cars/backup.env}
RESTIC_IMAGE=restic/restic:0.18.0
WORK=$(mktemp -d)
CONTAINER=premium-cars-restore-test

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "restoring the newest database dump"
docker run --rm --env-file "$ENV_FILE" -v "$WORK":/restore "$RESTIC_IMAGE" \
  restore latest --tag nightly --include /backup/database --target /restore
dump=$(find "$WORK" -name premiumcars.dump | head -1)
[ -s "$dump" ] || { echo "no database dump in the newest snapshot"; exit 1; }
ls -l "$dump"

echo "loading it into a throwaway PostgreSQL"
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=restore-test -v "$dump":/premiumcars.dump:ro \
  postgres:17-alpine >/dev/null
until docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
sleep 2
docker exec "$CONTAINER" createdb -U postgres premiumcars
docker exec "$CONTAINER" pg_restore -U postgres -d premiumcars --no-owner /premiumcars.dump
docker exec "$CONTAINER" psql -U postgres -d premiumcars -c \
  "SELECT (SELECT count(*) FROM car) AS cars, (SELECT count(*) FROM car_image) AS photos, (SELECT count(*) FROM inquiry) AS inquiries;"
echo "OK: the backup can be restored"
