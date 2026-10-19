# premium-cars-infra

Local infrastructure for Premium Cars Import and the "start here" guide (README.md, English).
Sibling repos: `premium-cars-backend` (Spring Boot, port 8080), `premium-cars-frontend` (Next.js, port 3000).

- `docker-compose.yml`: PostgreSQL 17 on 127.0.0.1:5433 (database/user `premiumcars`, password from `.env`,
  no default) and HashiCorp Vault on 127.0.0.1:8200 with the one-shot `vault-init`
  (`vault/scripts/vault-setup.sh`: init, unseal, KV v2, policy, AppRole, backend secret).
- The backend reads every secret from Vault `secret/premium-cars/backend` and its AppRole login from
  `vault/secrets/backend-approle.properties`; key names must match the backend's `application.yml` placeholders.
  Never commit anything from `vault/secrets/` (git-ignored) or a real `.env`.
- The schema is owned by Liquibase in the backend repo. Do not add SQL init scripts here (the only init script,
  `postgres/init-prod/01-app-user.sh`, creates the production login role; no tables).
- Production: `docker-compose.prod.yml` (project `premium-cars-prod`, `.env.prod`, `vault/secrets-prod/`), always run
  through `scripts/prod.sh`; `docker-compose.prod.local.yml` tries it locally. Never let a production change alter
  `docker-compose.yml` / the local setup. Server setup, backups, deploy: README "Production".
- Validate changes with `POSTGRES_PASSWORD=x docker compose config -q`; CI runs the whole Vault setup (local and
  production mode), validates the Caddyfile and shellchecks the scripts.
- Keep README.md in sync when ports, versions or start steps change.
