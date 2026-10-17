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
`FB_ACCESS_TOKEN`, `IG_USER_ID` and `IMGBB_API_KEY` are taken; anything else in the file is ignored.

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

## 4. GitHub and Claude Code

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
