# premium-cars-infra

Local infrastructure for Premium Cars Import and the "start here" guide (README.md, Bulgarian).
Sibling repos: `premium-cars-backend` (Spring Boot, port 8080), `premium-cars-frontend` (Next.js, port 3000).

- `docker-compose.yml`: PostgreSQL 17 on host port 5433, database/user/password `premiumcars`.
  The backend's `application.yml` defaults depend on these values; change both together.
- The schema is owned by Liquibase in the backend repo. Do not add SQL init scripts here.
- Validate changes with `docker compose config -q`.
- Keep README.md in sync when ports, versions or start steps change.
