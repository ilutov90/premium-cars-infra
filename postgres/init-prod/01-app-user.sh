#!/bin/sh
# Production only (docker-compose.prod.yml), runs once when the database is created: the backend's own login
# "premiumcars" owns the database but is not a superuser. Roles only: the schema is Liquibase's (backend repo).
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set pw="$APP_DB_PASSWORD" <<'SQL'
CREATE ROLE premiumcars LOGIN PASSWORD :'pw';
ALTER DATABASE premiumcars OWNER TO premiumcars;
ALTER SCHEMA public OWNER TO premiumcars;
SQL
