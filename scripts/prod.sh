#!/bin/sh
# docker compose for production: docker-compose.prod.yml with .env.prod (settings) and .env.tags (which image
# versions are deployed, written by `deploy`). Run from anywhere:
#   ./scripts/prod.sh up -d | ps | logs -f backend | pull | down
#   ./scripts/prod.sh deploy [backend-tag] [frontend-tag]   pull the images (default: latest) and restart
#     IMAGE_REGISTRY=registry.gitlab.com/<group> ./scripts/prod.sh deploy ...   the images of that registry (the
#     GitLab / Cloud Build deploy); without it GHCR (the GitHub deploy). Kept in .env.tags for later restarts.
#   ./scripts/prod.sh vault <bootstrap|import|keys|forget-root-token>
set -eu
cd "$(dirname "$0")/.."
[ -f .env.prod ] || { echo "missing .env.prod (copy .env.prod.example)"; exit 1; }

compose() {
  if [ -f .env.tags ]; then
    docker compose -f docker-compose.prod.yml --env-file .env.prod --env-file .env.tags "$@"
  else
    docker compose -f docker-compose.prod.yml --env-file .env.prod "$@"
  fi
}

case "${1:-}" in
  deploy)
    printf 'BACKEND_TAG=%s\nFRONTEND_TAG=%s\n' "${2:-latest}" "${3:-latest}" > .env.tags
    if [ -n "${IMAGE_REGISTRY:-}" ]; then
      printf 'IMAGE_REGISTRY=%s\n' "$IMAGE_REGISTRY" >> .env.tags
    fi
    compose pull backend frontend
    compose up -d --remove-orphans
    docker image prune -f >/dev/null
    compose ps
    ;;
  vault)
    shift
    # VAULT_TOKEN is passed on only when set in the shell (production keeps the root token in Bitwarden)
    compose run --rm -T -e VAULT_TOKEN vault-init "$@"
    ;;
  *)
    compose "$@"
    ;;
esac
