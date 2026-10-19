# premium-cars-infra

Start here. This repo holds the local database (PostgreSQL in Docker), the secrets store (HashiCorp Vault) and the guide for running the whole
Premium Cars Import project.

| Repo | What | Tech | Port |
|---|---|---|---|
| `premium-cars-backend` | REST API, import by link, pricing, inquiries | Java 21, Spring Boot 3.5, JdbcClient (no JPA), Liquibase | 8080 |
| `premium-cars-frontend` | public website + admin panel (UI in Bulgarian) | Next.js 16, React 19, TypeScript, Tailwind CSS 4 | 3000 |
| `premium-cars-infra` | local database and secrets | Docker Compose, PostgreSQL 17, HashiCorp Vault 1.20 | 5433, 8200 |

Keep the three repos side by side in one folder:

```
premium-cars/
├── premium-cars-backend/
├── premium-cars-frontend/
└── premium-cars-infra/
```

---

## 1. What to install (once)

| Program | Why |
|---|---|
| JDK 21 (Eclipse Temurin) | the backend |
| Maven 3.9+ | backend build (IntelliJ has one built in) |
| Node.js 22 LTS or a newer LTS | the frontend |
| Docker Desktop | PostgreSQL, Vault and the backend tests |
| Git | the repos |
| IntelliJ IDEA / VS Code | editors |

## 2. Run locally

```bash
# 1. database + Vault (secrets)
cd premium-cars-infra
cp .env.example .env               # once; set POSTGRES_PASSWORD (PowerShell: Copy-Item .env.example .env)
docker compose up -d               # also after every reboot: it unseals Vault
docker compose ps                  # postgres and vault: healthy; vault-init: exited (0)
docker compose logs vault-init     # what the Vault setup did

# 2. backend (new terminal) — reads all its secrets from Vault
cd premium-cars-backend
mvn spring-boot:run                # or Run PremiumCarsApplication in IntelliJ

# 3. frontend (new terminal)
cd premium-cars-frontend
cp .env.example .env.local         # once
npm install
npm run dev
```

Check:

- http://localhost:8080/api/public/cars → JSON with the demo cars
- http://localhost:3000 → the site
- http://localhost:3000/admin → user `admin`, password from `vault/secrets/admin-initial-password.txt`
  → change it under "Профил" → paste a link from global.autohome.com.cn or autowini.com → "Импортирай" (Import)

The first autohome import may take a minute longer: it downloads a headless Chromium (~150 MB) once.

Database: `localhost:5433`, database and user `premiumcars`, password from `.env`. Wipe all data:
`docker compose down -v` (also deletes Vault and its secrets).

## 3. Secrets: HashiCorp Vault

Every secret of the backend lives in Vault (KV v2, `secret/premium-cars/backend`): the database password,
the autowini login, the Facebook/Instagram token, the imgbb key and the first admin password. Nothing secret is
in git, in `application.yml` or in the backend's `.env`.

`docker compose up -d` runs `vault-init` once per start. On the first run it initialises Vault; every run it
unseals Vault and makes sure of the secret path, a read-only policy and an AppRole for the backend. It writes to
`vault/secrets/` (git-ignored, keep it private):

| File | What |
|---|---|
| `init.txt` | unseal key + root token (the root token opens the Vault UI) |
| `backend-approle.properties` | the backend's AppRole login, read by the backend at startup |
| `admin-initial-password.txt` | the first admin password (until you change it in the admin panel) |

**Move your existing `.env` into Vault (once).** The keys `AUTOWINI_USER`, `AUTOWINI_PASS`, `FB_PAGE_ID`,
`FB_ACCESS_TOKEN`, `IG_USER_ID`, `IMGBB_API_KEY`, `VIBER_CHANNEL_TOKEN` and `RESEND_API_KEY` are taken; anything else in the file is
ignored.

```bash
docker compose run --rm -T vault-init import < ../premium-cars-backend/.env
```
```powershell
Get-Content ..\premium-cars-backend\.env | docker compose run --rm -T vault-init import
```

Then delete those lines from `premium-cars-backend/.env` (or the whole file) and restart the backend.
Check what is stored (values hidden): `docker compose run --rm vault-init keys`.

**Change a value:** http://127.0.0.1:8200 → sign in with *Token* = the root token from `vault/secrets/init.txt`
→ `secret/` → `premium-cars/backend` → *Create new version* → edit → *Save*. Restart the backend.

**Change the database password.** `POSTGRES_PASSWORD` only applies when the database is created. For an existing
database (the old default was `premiumcars`):

```bash
docker compose exec postgres psql -U premiumcars -d premiumcars -c "ALTER USER premiumcars PASSWORD 'the-new-password'"
```

then put the same value in `.env` as `POSTGRES_PASSWORD` and run `docker compose up -d` (the setup copies it to
Vault as `DB_PASSWORD`). To keep the old password instead, set `POSTGRES_PASSWORD=premiumcars` in `.env`.

Local Vault runs without TLS and listens on 127.0.0.1 only. Production gets its own Vault with TLS and the
unseal key kept outside the server (deploy step).

### Windows: "npm.ps1 cannot be loaded because running scripts is disabled"

PowerShell blocks npm's script wrapper by default. Either run once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

or use `npm.cmd install` / `npm.cmd run dev`, or run the commands from Command Prompt / Git Bash.

---

## 4. Production (premiumcarsimport.bg)

The site runs on one server with Docker Compose: `docker-compose.prod.yml`. It never replaces the local setup:
own project name (`premium-cars-prod`), own volumes, own secrets folder (`vault/secrets-prod/`), own env file
(`.env.prod`). Always go through `./scripts/prod.sh`, which adds the env files:

```
internet ──▶ Caddy :80/:443 (Let's Encrypt) ──┬─ /api/*, /media/* ──▶ backend :8080 ──▶ PostgreSQL, Vault
                                              └─ everything else ──▶ frontend :3000
```

| File | What |
|---|---|
| `docker-compose.prod.yml` | Caddy, frontend + backend (images from GHCR), PostgreSQL, Vault, vault-init |
| `caddy/Caddyfile` | HTTPS, `www.` → main domain, `/api` and `/media` to the backend, HSTS |
| `postgres/init-prod/01-app-user.sh` | first start only: database user `premiumcars` (owner, not superuser) |
| `.env.prod.example` | domain, Let's Encrypt e-mail, database passwords, inquiry e-mail address |
| `scripts/prod.sh` | `docker compose` for production; `deploy [backend-tag] [frontend-tag]`; `vault …` |
| `scripts/server-setup.sh` | one-time server setup (updates, Docker, users `admin` + `deploy`, SSH keys only, no root login, firewall, fail2ban, swap) |
| `scripts/backup.sh`, `systemd/*` | nightly backup (database, photos, Vault) with restic to Cloudflare R2 |
| `scripts/restore-test.sh` | restores the newest backup into a throwaway database and counts the rows |
| `.github/workflows/deploy.yml` | Actions → Deploy → Run workflow: pull images on the server and restart |

Images: CI of the backend and frontend repos pushes `ghcr.io/ilutov90/premium-cars-backend` / `-frontend` with the
tags `latest` and the commit SHA on every merge to main. Deploying is a separate, manual step.

### Try it on your computer first

```powershell
Copy-Item .env.prod.example .env.prod.local   # set ACME_EMAIL and the two passwords (any values)
docker compose -f docker-compose.prod.yml -f docker-compose.prod.local.yml --env-file .env.prod.local up -d --build
docker compose -f docker-compose.prod.yml -f docker-compose.prod.local.yml --env-file .env.prod.local logs vault-init
```

Builds the images from `../premium-cars-backend` and `../premium-cars-frontend`, serves https://localhost (accept
the browser's warning about Caddy's local certificate). First admin password:
`vault/secrets-prod-local/admin-initial-password.txt`. Secrets: same `import` as locally, with
`-f docker-compose.prod.yml -f docker-compose.prod.local.yml --env-file .env.prod.local run --rm -T vault-init import`.
Stop with `… down` (`down -v` wipes this test's data). The development setup (`docker compose up -d`) is untouched.

### Server setup (once)

Two users on the server: **`admin`** (you, with sudo; for `sudo …` commands) and **`deploy`** (no sudo; owns the
app in `/opt/premium-cars`, runs `prod.sh`, used by GitHub Actions). Both log in with your SSH key only.

1. From your computer, as the provider gives you the server:
   - logged in as **root** (netcup): `scp scripts/server-setup.sh root@<IP>:` then `ssh root@<IP>` and
     `bash server-setup.sh` — creates `admin` with root's SSH keys and turns root login off;
   - with a sudo user (e.g. `ubuntu`): `scp …` / `ssh ubuntu@<IP>` and `sudo bash server-setup.sh` (`ubuntu` is the admin).

   Before closing the root session, check in a second terminal that `ssh admin@<IP>` and `sudo -v` work.
2. GitHub → premium-cars-infra → Settings → Deploy keys → Add the key the script printed (read-only).
3. `ssh deploy@<IP>`, then:
   ```bash
   git clone git@github.com:ilutov90/premium-cars-infra.git /opt/premium-cars/premium-cars-infra
   cd /opt/premium-cars/premium-cars-infra
   cp .env.prod.example .env.prod && nano .env.prod      # passwords: openssl rand -hex 24
   docker login ghcr.io -u ilutov90                      # password: a GitHub token with read:packages only
   ```
4. DNS (Cloudflare, "DNS only"): `A premiumcarsimport.bg → <IP>` and `A www → <IP>`.

### First deploy

As `deploy` in `/opt/premium-cars/premium-cars-infra`; the `sudo` lines in a second terminal as `admin`
(`cd /opt/premium-cars/premium-cars-infra` first).

```bash
./scripts/prod.sh deploy                       # pulls the images, starts everything, Caddy gets the certificate
sudo cat vault/secrets-prod/init.txt           # unseal key + root token -> Bitwarden
read -rs VAULT_TOKEN; export VAULT_TOKEN       # paste the root token (not saved anywhere)
./scripts/prod.sh vault import < secrets.env   # a KEY=VALUE file you typed on the server; delete it afterwards
./scripts/prod.sh vault forget-root-token      # the root token leaves the server; restarts still unseal
unset VAULT_TOKEN
sudo cat vault/secrets-prod/admin-initial-password.txt   # log in, change it under Профил, then delete the file
```

The import takes `AUTOWINI_USER`, `AUTOWINI_PASS`, `FB_PAGE_ID`, `FB_ACCESS_TOKEN`, `IG_USER_ID`, `IMGBB_API_KEY`,
`VIBER_CHANNEL_TOKEN`, `RESEND_API_KEY`. After changing secrets: `./scripts/prod.sh restart backend`.

### Deploying a new version

GitHub → premium-cars-infra → Actions → **Deploy** → Run workflow (tags: `latest`, or a commit SHA to roll back).
Repository secrets: `DEPLOY_HOST` (IP), `DEPLOY_SSH_KEY` (a private key for user `deploy`; its public key goes into
`/home/deploy/.ssh/authorized_keys`), `DEPLOY_KNOWN_HOSTS` (`ssh-keyscan <IP>`). By hand on the server:
`./scripts/prod.sh deploy [backend-tag] [frontend-tag]`.

### Backups

As `admin`, in `/opt/premium-cars/premium-cars-infra`:

```bash
sudo mkdir -p /etc/premium-cars
sudo cp scripts/backup.env.example /etc/premium-cars/backup.env && sudo chmod 600 /etc/premium-cars/backup.env
sudo nano /etc/premium-cars/backup.env         # R2 bucket + keys, restic password (also in Bitwarden)
sudo ./scripts/backup.sh                       # first backup now
sudo cp systemd/premium-cars-backup.* /etc/systemd/system/ && sudo systemctl daemon-reload
sudo systemctl enable --now premium-cars-backup.timer     # every night at 03:30 UTC
sudo ./scripts/restore-test.sh                 # proves the backup can be restored (do it every few months)
```

### Restore from a backup (new server)

Server setup as above, clone, `.env.prod` with the same passwords, `/etc/premium-cars/backup.env`, then restore the
newest snapshot (`docker run --rm --env-file /etc/premium-cars/backup.env -v /tmp/restore:/restore
restic/restic:0.18.0 restore latest --target /restore`) and copy back: `backup/vault-secrets/` →
`vault/secrets-prod/`, `backup/vault-data/` and `backup/media/` into the volumes `premium-cars-prod_vaultdata` and
`premium-cars-prod_media`, the database with `pg_restore` (`./scripts/prod.sh exec -T postgres pg_restore -U postgres
-d premiumcars --clean --if-exists < premiumcars.dump`). Then `./scripts/prod.sh up -d`.

### Production Vault

Same script as locally, in production mode: after `forget-root-token` the server keeps only the unseal key (so a
restart unseals by itself) and the backend's AppRole file (readable only by the backend's user). The root token is in
Bitwarden; `vault import`, `vault keys` and the Vault UI need it. The Vault UI is not exposed; to use it:
`ssh -L 8200:<vault container IP>:8200 deploy@<IP>` or the CLI through `./scripts/prod.sh exec vault vault …`.

## 5. GitHub and Claude Code

The code lives in three private GitHub repos. Claude Code works on them directly from claude.ai/code
(browser or phone): it creates a branch, makes the change, runs the tests and opens a pull request. You review
it and press Merge.

Each repo has:

- `CLAUDE.md`: how to build and test, and the rules (e.g. "no JPA, only JdbcClient"). Claude reads it on every task.
- `.github/workflows/ci.yml`: checks on every push and pull request:
  - backend: `mvn verify`, including the tests against PostgreSQL in Docker;
  - frontend: `npm run lint` and `npm run build`;
  - infra: validation of `docker-compose.yml` and the whole Vault setup against a real Vault;
  - all three: gitleaks (no passwords, tokens or keys in commits).

### On your computer after Claude's changes are merged

```bash
cd premium-cars-backend
git checkout main
git pull                 # get the merged changes
```

To continue locally a task Claude started: `claude --teleport` in the repo folder.

### Local Claude Code (optional)

Install Claude Code (see code.claude.com/docs) and run `claude` in a repo folder. Handy for tasks you want to
watch closely or test against the local database.
