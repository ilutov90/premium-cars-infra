# premium-cars-infra

Start here. This repo holds the local database (PostgreSQL in Docker) and the guide for running the whole
Premium Cars Import project.

| Repo | What | Tech | Port |
|---|---|---|---|
| `premium-cars-backend` | REST API, import by link, pricing, inquiries | Java 21, Spring Boot 3.5, JdbcClient (no JPA), Liquibase | 8080 |
| `premium-cars-frontend` | public website + admin panel (UI in Bulgarian) | Next.js 16, React 19, TypeScript, Tailwind CSS 4 | 3000 |
| `premium-cars-infra` | local database | Docker Compose, PostgreSQL 17 | 5433 |

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
| Docker Desktop | PostgreSQL and the backend tests |
| Git | the repos |
| IntelliJ IDEA / VS Code | editors |

## 2. Run locally

```bash
# 1. database
cd premium-cars-infra
docker compose up -d
docker compose ps                  # STATUS: healthy

# 2. backend (new terminal)
cd premium-cars-backend
cp .env.example .env               # once; fill in AUTOWINI_USER / AUTOWINI_PASS
mvn spring-boot:run                # or Run PremiumCarsApplication in IntelliJ

# 3. frontend (new terminal)
cd premium-cars-frontend
cp .env.example .env.local         # PowerShell: Copy-Item .env.example .env.local
npm install
npm run dev
```

Check:

- http://localhost:8080/api/public/cars → JSON with the demo cars
- http://localhost:3000 → the site
- http://localhost:3000/admin → log in with `admin` / `admin123` → paste a link from global.autohome.com.cn
  or autowini.com → "Импортирай" (Import)

The first autohome import may take a minute longer: it downloads a headless Chromium (~150 MB) once.

Database: `localhost:5433`, database/user/password `premiumcars`. Wipe all data: `docker compose down -v`.

### Windows: "npm.ps1 cannot be loaded because running scripts is disabled"

PowerShell blocks npm's script wrapper by default. Either run once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

or use `npm.cmd install` / `npm.cmd run dev`, or run the commands from Command Prompt / Git Bash.

---

## 3. GitHub and Claude Code

The code lives in three private GitHub repos. Claude Code works on them directly from claude.ai/code
(browser or phone): it creates a branch, makes the change, runs the tests and opens a pull request. You review
it and press Merge.

Each repo has:

- `CLAUDE.md`: how to build and test, and the rules (e.g. "no JPA, only JdbcClient"). Claude reads it on every task.
- `.github/workflows/ci.yml`: checks on every push and pull request:
  - backend: `mvn verify`, including the tests against PostgreSQL in Docker;
  - frontend: `npm run lint` and `npm run build`;
  - infra: validation of `docker-compose.yml`.

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
