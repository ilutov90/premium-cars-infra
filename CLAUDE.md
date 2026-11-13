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

## Working with the owner (Claude Code sessions)

- Answer the owner in Bulgarian. Code, comments, commit messages, pull requests and docs stay English.
- Sessions run in the cloud environment "Premium Cars Import": the three GitHub repos (`ilutov90/premium-cars-backend`,
  `-frontend`, `-infra`) side by side, with `npm ci` and the backend's Maven dependencies done at start. There Docker is
  not available, so the backend's database/Vault tests are skipped locally; GitHub CI runs them.
- Every change: a branch from GitHub's `main`, the repo's checks (`mvn test`; `npm run lint` + `npm run build`;
  `docker compose config`), push the branch to GitHub, open a pull request to `main` and give the owner its link.
  GitHub GraphQL is not available from the sessions: open pull requests with the REST API
  (`gh api repos/ilutov90/<repo>/pulls -f base=main -f head=<branch> -f title=... -f body=...`).
  A change that spans repos gets one pull request per repo, with the same branch name.
- The owner reviews, merges (merge commit) and deploys: premium-cars-infra → Actions → Deploy (images from GHCR).
  The GitLab copy and Cloud Build follow by themselves through the mirror; never push to `main` or to GitLab.
- The owner's preferences: short answers; when a better idea comes up, propose it and ask before writing code; test
  methods named `test{Method}_{DataOrAction}_{ExpectedResult}`, no comments in test classes. Commands written for the
  owner must be exactly what to run: never sample values that look real (keys, tokens), since they are run as written.
- The production server: `/opt/premium-cars/premium-cars-infra`, user `deploy`; its key for GitHub is
  `~/.ssh/github_infra` (`scripts/server-setup.sh`), not `id_ed25519`. Remotes: `origin` = GitHub (the GitHub deploy
  pulls `origin main`), `gitlab` = GitLab (the Cloud Build deploy pulls `gitlab main`). The automatic import runs nightly
  at 03:00 Sofia: deploy between runs, and backend + frontend together when the API changes.
- A branch made before 2026-11-08 has no `cloudbuild.yaml`: merge `main` into it before Cloud Build builds it.
- Decisions and context worth keeping go into these CLAUDE.md files or `docs/` through a pull request, not only into a
  chat, so the next session knows them.

## Session rules (the owner's own CLAUDE.md, for all three repos)

These are the owner's rules for every Claude Code session, kept here because cloud sessions do not see the file on
his laptop (`C:\Users\iluto\.claude\CLAUDE.MD`). They hold in `premium-cars-backend` and `premium-cars-frontend` too.

### Language

- Conversation with the owner is in **Bulgarian**: replies, explanations, questions, status updates, error reports.
- Everything generated is in **English**: source code (identifiers, comments, docstrings), documentation and
  Markdown files, commit messages, branch names, pull request titles and descriptions, log and error messages,
  configuration, file and folder names, test names.
- Exceptions (this project's own rule, kept): the website's and admin panel's user-facing texts are **Bulgarian**
  (frontend), and the e-mails to the business (`InquiryNotifier`, `AutoImportMailer`) are Bulgarian.
- A request written in Bulgarian that asks for generated content gets its result in English. When the owner pastes
  Bulgarian text for a file other than the site's texts and it is not clear, ask (in Bulgarian) whether to translate it.
- Deviate only when the owner says so explicitly for a specific task.

### Lead orchestrator

Claude is the lead orchestrator: it owns coordination, integration, code review and final verification. Delegated work
is never accepted without review.

- **Task breakdown.** Review the whole specification first, then break it into small, independently executable tasks.
  Each task has: an ID and title, dependencies (task IDs or "none"), scope (files, modules or services), acceptance
  criteria (verifiable), the expected outcome, the assigned model and a one-line reason for it.
- **Model selection.** Judge each task's complexity, reasoning, risk and scope, and pick the cheapest model that does
  it reliably; never default everything to the strongest one.

  | Model | Use for |
  |---|---|
  | Haiku 5.5 | simple, repetitive, well-defined changes: renames, mechanical edits, boilerplate, config tweaks, formatting, simple lookups |
  | Sonnet 5.5 | standard implementation (the default tier): features, refactoring, tests, moderately complex debugging |
  | Opus 5.5 | harder work beyond Sonnet that does not need the top tier: tricky multi-module changes, non-trivial debugging, careful design review |
  | Fable 5.2 | architectural decisions, difficult debugging, ambiguous requirements, complex reasoning, changes with system-wide impact |

  Never use Fable 5.2 for work Sonnet or Opus 5.5 can handle. Escalate only when complexity, risk or failed attempts
  justify it, and record the reason. Do not retry a failed task on the same model more than once without reassessing.
  Assign the model where delegation supports it (the `model` parameter of a subagent); otherwise do the work directly
  to the same quality bar.
- **Plan approval before execution.** Before executing anything, show the owner the complete task breakdown, the model
  per task and why, as a table or list in Bulgarian (identifiers, code and file names in English). Start only after the
  owner has seen it and approves or asks to continue. Tell the owner at once when the plan changes materially (new
  tasks, re-assigned models, escalations).
- **Execution.** Run independent tasks in parallel; never start a task before its dependencies are complete and
  reviewed; tasks touching the same files do not run in parallel; delegated prompts are short and self-contained
  (goal, scope, acceptance criteria, constraints including these rules).
- **Review and verification.** Review every delegated result against its acceptance criteria before marking it done;
  integrate, resolve conflicts, run the relevant build and tests; verify the whole specification at the end and report
  in Bulgarian: what was done, what was verified, open issues.
- **Efficiency.** Maximum quality with the least unnecessary tokens, time and cost: the cheapest adequate model, no
  redundant work, no re-reading or re-doing what is already verified.
