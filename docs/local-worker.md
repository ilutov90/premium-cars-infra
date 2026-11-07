# Automatic import from a laptop (local worker)

When guazi or autowini block the production server's address, the automatic import can run from an admin's
Windows laptop instead: the laptop runs the backend (profile `worker`) and the frontend against the **production
database**, so the sites see the laptop's address. Everything else (the site, scheduled posts, photo moves,
Liquibase) stays with production.

Only one server may run the automatic import at a time: production is switched off for it first
(`AUTO_IMPORT_ENABLED=false`), and the laptop script refuses to start until it is.

## What protects production

- **One importer.** `app.auto-import.enabled` (backend `AutoImportInstance`): production with `false` skips the
  nightly run and its queue, refuses "run now", the preview and the sites' lists, and does not mark the laptop's
  runs as interrupted when it restarts. Its admin panel says so.
- **The laptop does only the import.** Profile `worker` (`application-worker.yml`): Liquibase off (the laptop never
  changes the schema), `app.background-jobs=false` (no scheduled posts, no R2 photo mover, no stored-photo linker,
  no clean-up of production's interrupted posts or recalculations).
- **Same code as production.** The script checks that the backend and frontend are on `origin/main`.
- **No open ports.** PostgreSQL and Vault stay unpublished; the laptop reaches them through an SSH tunnel as
  `deploy`. The backend's AppRole (read-only on its secrets) and settings come from the running backend container
  (`scripts/local-worker-info.sh`, which changes nothing) and live only in the laptop processes' environment.
- **Gentle on the sites.** Searches and each site's queue 2 s apart, autowini photos 1 s apart (both servers).

## Needed on the laptop

Java 21, Maven, Node.js (npm), Git and the Windows OpenSSH client (`ssh`), with the SSH key that logs in as
`deploy`. The three repositories side by side, e.g. `C:\dev\premium-cars-backend`, `C:\dev\premium-cars-frontend`,
`C:\dev\premium-cars-infra`.

## 1. Code

Merge and deploy the backend and frontend versions that have `app.auto-import.enabled` (GitHub Actions → Deploy,
or `./scripts/prod.sh deploy` on the server). On the server, as `deploy`:

```sh
cd /opt/premium-cars/premium-cars-infra && git pull
```

On the laptop, in each of the three repositories: `git checkout main` and `git pull`.

## 2. Switch production's import off

On the server, as `deploy`, in `/opt/premium-cars/premium-cars-infra`:

```sh
grep -q '^AUTO_IMPORT_ENABLED=' .env.prod \
  && sed -i 's/^AUTO_IMPORT_ENABLED=.*/AUTO_IMPORT_ENABLED=false/' .env.prod \
  || echo 'AUTO_IMPORT_ENABLED=false' >> .env.prod
./scripts/prod.sh up -d          # recreates the backend with the new setting (the site's API is back in ~30 s)
./scripts/prod.sh exec backend printenv APP_AUTO_IMPORT_ENABLED     # false
```

The production admin panel's "Автоматичен импорт" page now says the import does not run from that server.

## 3. Start on the laptop

In PowerShell, in the infra repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\local-worker.ps1
```

It opens the tunnel, starts the backend and the frontend in two windows and waits for the backend (the first start
downloads Maven dependencies; the first guazi page downloads the headless Chromium, ~150 MB). When it prints
`READY`, open http://localhost:3000/admin/auto-import and log in as usual. The settings, queue, reports and cars
are production's; "Пусни сега", "Преглед" and the nightly 03:00 run now work from the laptop (keep it on and
awake). Press Enter in the script's window to stop everything.

Options: `-Server deploy@<IP>`, `-Backend <path>`, `-Frontend <path>` (defaults: the sibling folders).

## 4. Back to production

When the server's address is no longer blocked (or a new address is set up): stop the laptop script, then on the
server set `AUTO_IMPORT_ENABLED=true` in `.env.prod` and run `./scripts/prod.sh up -d`.

## Troubleshooting

- *production still runs the automatic import itself*: step 2 was not done (or `up -d` not run).
- *port … is in use*: a local development backend/frontend/database is running; stop it.
- *the SSH tunnel did not open*: check `ssh deploy@<IP>` works; production must be running.
- Backend window: `Connection refused` to Vault or PostgreSQL means the tunnel closed: restart the script.
