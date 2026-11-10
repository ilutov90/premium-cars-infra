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
- `AUTO_IMPORT_ENABLED` (`.env.prod`, default true) -> the backend's `APP_AUTO_IMPORT_ENABLED`: false while a laptop runs the
  automatic import against the production database (`scripts/local-worker.ps1` + `scripts/local-worker-info.sh`,
  `docs/local-worker.md`). Only one of them may run it.
- Where the code lives: GitHub (`ilutov90/premium-cars-*`) is the main place: a branch from `main`, a pull request
  to `main`, merged there with a merge commit (not squash or rebase, so GitLab's `main` stays an ancestor). Never push
  to `main`. GitLab (`premium-cars-import/premium-cars-*`) is only updated by each repo's
  `.github/workflows/mirror-gitlab.yml` (pushes `main` after every push to GitHub's `main`, never forced, token
  `GITLAB_MIRROR_TOKEN` in a header). Do not push branches or merge requests to GitLab.
- Two ways to build and deploy: GitHub (main: `.github/workflows`, images in GHCR, Actions -> Deploy) and, as the
  backup, GitLab + Google Cloud Build (`cloudbuild*.yaml`, images in `registry.gitlab.com/<group>`,
  docs/gitlab-cloud-build.md). `prod.sh deploy` takes the registry from `IMAGE_REGISTRY` in its environment (Cloud
  Build's deploy sets it) and keeps it in `.env.tags`; without it GHCR. Keep the two in step when the CI or the
  deploy changes.
