# premium-cars-infra

Local infrastructure for Premium Cars Import and the "start here" guide (README.md, English).
Sibling repos: `premium-cars-backend` (Spring Boot, port 8080), `premium-cars-frontend` (Next.js, port 3000).

- `docker-compose.yml`: PostgreSQL 17 on 127.0.0.1:5433 (database/user `premiumcars`, password from `.env`,
  no default) and HashiCorp Vault on 127.0.0.1:8200 with the one-shot `vault-init`
  (`vault/scripts/vault-setup.sh`: init, unseal, KV v2, policy, AppRole, backend secret).
- The backend reads every secret from Vault `secret/premium-cars/backend` and its AppRole login from
  `vault/secrets/backend-approle.properties`; key names must match the backend's `application.yml` placeholders.
  Never commit anything from `vault/secrets/` (git-ignored) or a real `.env`.
- The schema is owned by Liquibase in the backend repo. Do not add SQL init scripts here.
- Validate changes with `POSTGRES_PASSWORD=x docker compose config -q`; CI runs the whole Vault setup.
- Keep README.md in sync when ports, versions or start steps change.
