#!/usr/bin/env bash
# Runs once, on the first start of an empty Postgres volume (docker-entrypoint-initdb.d).
# Creates one database and one role per service (docs/database/00-create-databases.sql).
# Each role owns its database, so the service creates its own tables: EF Core migrations are the
# single source of truth for the schema, applied on startup (Database__MigrateOnStartup=true).
set -euo pipefail

: "${IDENTITY_DB_PASSWORD:?IDENTITY_DB_PASSWORD is required}"
: "${VIDEO_DB_PASSWORD:?VIDEO_DB_PASSWORD is required}"
: "${NOTIFICATION_DB_PASSWORD:?NOTIFICATION_DB_PASSWORD is required}"

echo "fiapx: creating databases and roles"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v identity_pwd="'${IDENTITY_DB_PASSWORD}'" \
  -v video_pwd="'${VIDEO_DB_PASSWORD}'" \
  -v notification_pwd="'${NOTIFICATION_DB_PASSWORD}'" \
  -f /fiapx/database/00-create-databases.sql
