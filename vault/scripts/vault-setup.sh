#!/bin/sh
# Local Vault setup for Premium Cars. Runs inside the vault-init container (hashicorp/vault image), so it works the
# same on Windows, macOS and Linux.
#
#   bootstrap   (default; runs on every `docker compose up`)
#               first run: initialise Vault (1 key share), save the unseal key and root token
#               every run: unseal, enable KV v2 at secret/, write the backend policy and AppRole, make sure the
#               backend secret exists with DB_USERNAME / DB_PASSWORD (from POSTGRES_PASSWORD) and an
#               ADMIN_INITIAL_PASSWORD, write the AppRole credentials for the backend
#   import      read KEY=VALUE lines (a .env file) from stdin and store the known keys in the backend secret:
#               docker compose run --rm -T vault-init import < ../premium-cars-backend/.env
#   keys        list the keys stored in the backend secret (values are not printed)
#   forget-root-token
#               production: remove the root token from init.txt (keep it in Bitwarden). Unsealing still works;
#               bootstrap then only unseals, and import / keys need the token: docker compose run --rm
#               -e VAULT_TOKEN -T vault-init import (VAULT_TOKEN set in the shell, not in a file)
#
# Files in /vault/secrets (= premium-cars-infra/vault/secrets, git-ignored):
#   init.txt                        unseal key and root token (local only; keep them out of git and chats)
#   backend-approle.properties      AppRole role-id / secret-id, read by the backend at startup
#                                   (APPROLE_FILE; production: backend/backend-approle.properties, the only
#                                   folder mounted into the backend container)
#   admin-initial-password.txt      the generated first admin password (until you change it in the admin panel)
set -eu

SECRETS=/vault/secrets
INIT_FILE="$SECRETS/init.txt"
APPROLE_FILE="${APPROLE_FILE:-$SECRETS/backend-approle.properties}"
ADMIN_FILE="$SECRETS/admin-initial-password.txt"
SECRET_PATH=secret/premium-cars/backend
POLICY=premium-cars-backend
ROLE=premium-cars-backend
# Keys `import` accepts (same names as the posting script's and the backend's .env)
KNOWN_KEYS="AUTOWINI_USER AUTOWINI_PASS FB_PAGE_ID FB_ACCESS_TOKEN IG_USER_ID IMGBB_API_KEY VIBER_CHANNEL_TOKEN RESEND_API_KEY ADMIN_INITIAL_PASSWORD"

log() { echo "[vault-setup] $*"; }

random_password() {
  # 24 characters, letters and digits only (safe in .properties, shells and URLs)
  head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24
}

wait_for_vault() {
  i=0
  until vault status >/dev/null 2>&1 || [ $? -eq 2 ]; do # exit 2 = sealed, still reachable
    i=$((i + 1))
    [ "$i" -gt 60 ] && { log "Vault at $VAULT_ADDR does not answer"; exit 1; }
    sleep 1
  done
}

initialised() {
  vault status -format=json 2>/dev/null | grep -q '"initialized": true'
}

sealed() {
  vault status -format=json 2>/dev/null | grep -q '"sealed": true'
}

unseal_key() { sed -n 's/^Unseal Key 1: //p' "$INIT_FILE"; }
root_token() { sed -n 's/^Initial Root Token: //p' "$INIT_FILE"; }

# Production: the backend container runs as uid APPROLE_OWNER and must be able to read its AppRole file.
own_approle() {
  if [ -n "${APPROLE_OWNER:-}" ] && [ -s "$APPROLE_FILE" ]; then
    chown "$APPROLE_OWNER" "$(dirname "$APPROLE_FILE")" "$APPROLE_FILE"
    chmod 700 "$(dirname "$APPROLE_FILE")"
    chmod 400 "$APPROLE_FILE"
  fi
}

# The root token: VAULT_TOKEN from the environment, else init.txt. Returns 1 when there is none (production).
login_root() {
  token=${VAULT_TOKEN:-}
  if [ -z "$token" ] && [ -s "$INIT_FILE" ]; then
    token=$(root_token)
  fi
  [ -n "$token" ] || return 1
  VAULT_TOKEN=$token
  export VAULT_TOKEN
}

require_root() {
  login_root || {
    log "no root token: init.txt has none (production). Run with the token from Bitwarden in VAULT_TOKEN:"
    log "  read -rs VAULT_TOKEN; export VAULT_TOKEN; ./scripts/prod.sh run --rm -e VAULT_TOKEN -T vault-init $1"
    exit 1
  }
}

unseal() {
  if sealed; then
    [ -s "$INIT_FILE" ] || { log "missing $INIT_FILE (unseal key); cannot unseal"; exit 1; }
    log "unsealing"
    vault operator unseal "$(unseal_key)" >/dev/null
  fi
}

secret_exists() { vault kv get "$SECRET_PATH" >/dev/null 2>&1; }

secret_has() { vault kv get -field="$1" "$SECRET_PATH" >/dev/null 2>&1; }

# put on the first write, patch (keep the other keys) afterwards
store() {
  if secret_exists; then
    vault kv patch "$SECRET_PATH" "$@" >/dev/null
  else
    vault kv put "$SECRET_PATH" "$@" >/dev/null
  fi
}

bootstrap() {
  wait_for_vault
  if ! initialised; then
    if [ -s "$INIT_FILE" ]; then
      log "Vault is empty but $INIT_FILE exists (old keys?). Move that file away and run again."
      exit 1
    fi
    log "initialising Vault (first run)"
    umask 077
    vault operator init -key-shares=1 -key-threshold=1 > "$INIT_FILE"
  fi
  unseal
  if ! login_root; then
    # production after forget-root-token: unsealing is all that is needed on a restart
    if [ -s "$APPROLE_FILE" ]; then
      own_approle
      log "unsealed; no root token on disk, so the setup is skipped (run bootstrap with VAULT_TOKEN to redo it)"
      log "ready"
      exit 0
    fi
    log "no root token and no AppRole file: cannot set up the backend's access"
    exit 1
  fi

  if ! vault secrets list -format=json | grep -q '"secret/"'; then
    log "enabling KV v2 at secret/"
    vault secrets enable -path=secret -version=2 kv >/dev/null
  fi

  log "writing policy $POLICY (read-only on $SECRET_PATH)"
  vault policy write "$POLICY" - >/dev/null <<EOF
# backend* also covers the profile variants Spring Cloud Vault looks up (backend/dev, backend,dev): 404, not 403
path "secret/data/premium-cars/backend*" {
  capabilities = ["read"]
}
EOF

  if ! vault auth list -format=json | grep -q '"approle/"'; then
    log "enabling AppRole auth"
    vault auth enable approle >/dev/null
  fi
  vault write "auth/approle/role/$ROLE" token_policies="$POLICY" token_ttl=1h token_max_ttl=24h \
    secret_id_ttl=0 secret_id_num_uses=0 >/dev/null

  # Database credentials follow premium-cars-infra/.env
  store DB_USERNAME="${POSTGRES_USER:-premiumcars}" DB_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is not set}"

  if ! secret_has ADMIN_INITIAL_PASSWORD; then
    pw=$(random_password)
    store ADMIN_INITIAL_PASSWORD="$pw"
    umask 077
    printf 'Admin panel, first login\nuser:     admin\npassword: %s\nChange it in the admin panel (Профил) after the first login.\n' "$pw" > "$ADMIN_FILE"
    log "generated the first admin password: see vault/secrets/admin-initial-password.txt"
  fi

  if [ ! -s "$APPROLE_FILE" ]; then
    role_id=$(vault read -field=role_id "auth/approle/role/$ROLE/role-id")
    secret_id=$(vault write -f -field=secret_id "auth/approle/role/$ROLE/secret-id")
    umask 077
    mkdir -p "$(dirname "$APPROLE_FILE")"
    {
      echo "# Written by premium-cars-infra/vault/scripts/vault-setup.sh. Git-ignored."
      echo "spring.cloud.vault.app-role.role-id=$role_id"
      echo "spring.cloud.vault.app-role.secret-id=$secret_id"
    } > "$APPROLE_FILE"
    log "wrote AppRole credentials for the backend"
  fi
  own_approle

  log "ready"
  keys
}

import_env() {
  wait_for_vault
  unseal
  require_root import
  # tr -d '\r': .env files saved on Windows
  tr -d '\r' | while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    key=$(echo "$key" | tr -d ' ')
    # strip surrounding quotes
    case "$value" in \"*\") value=${value#\"}; value=${value%\"} ;; \'*\') value=${value#\'}; value=${value%\'} ;; esac
    [ -z "$value" ] && continue
    case "$value" in
      @*|-) log "skipped $key: a value starting with @ or a lone - is read as a file by the Vault CLI; set it in the UI"; continue ;;
    esac
    for known in $KNOWN_KEYS; do
      if [ "$key" = "$known" ]; then
        store "$key=$value"
        log "stored $key"
      fi
    done
  done
  keys
}

keys() {
  log "keys in $SECRET_PATH (values hidden):"
  vault kv get -format=json "$SECRET_PATH" | sed -n '/"data": {/,/}/p' | sed -n 's/^ *"\([A-Z_]*\)": .*/  \1/p' | sort -u
}

forget_root_token() {
  [ -s "$INIT_FILE" ] || { log "missing $INIT_FILE"; exit 1; }
  if [ -z "$(root_token)" ]; then
    log "init.txt has no root token already"
    return
  fi
  umask 077
  grep '^Unseal Key 1:' "$INIT_FILE" > "$INIT_FILE.tmp"
  mv "$INIT_FILE.tmp" "$INIT_FILE"
  log "root token removed from init.txt (the unseal key stays, so restarts still unseal)."
  log "Keep the root token in Bitwarden: it is needed for import, keys and the Vault UI."
}

case "${1:-bootstrap}" in
  bootstrap) bootstrap ;;
  import) import_env ;;
  keys) wait_for_vault; unseal; require_root keys; keys ;;
  forget-root-token) forget_root_token ;;
  *) echo "usage: vault-setup.sh [bootstrap|import|keys|forget-root-token]"; exit 2 ;;
esac
