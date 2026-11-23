#!/usr/bin/env bash
# Runs once, on the first start of an empty Postgres volume (docker-entrypoint-initdb.d).
# 1. Creates one database and one role per service (docs/database/00-create-databases.sql).
# 2. Applies each service schema as the service role, so the tables are owned by it
#    (skip with FIAPX_DB_APPLY_SCHEMA=false when the services apply their own EF Core migrations).
set -euo pipefail

scripts=/fiapx/database

: "${IDENTITY_DB_PASSWORD:?IDENTITY_DB_PASSWORD is required}"
: "${VIDEO_DB_PASSWORD:?VIDEO_DB_PASSWORD is required}"
: "${NOTIFICATION_DB_PASSWORD:?NOTIFICATION_DB_PASSWORD is required}"

echo "fiapx: creating databases and roles"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v identity_pwd="'${IDENTITY_DB_PASSWORD}'" \
  -v video_pwd="'${VIDEO_DB_PASSWORD}'" \
  -v notification_pwd="'${NOTIFICATION_DB_PASSWORD}'" \
  -f "$scripts/00-create-databases.sql"

if [ "${FIAPX_DB_APPLY_SCHEMA:-true}" != "true" ]; then
  echo "fiapx: FIAPX_DB_APPLY_SCHEMA=${FIAPX_DB_APPLY_SCHEMA}, leaving schemas to the services' migrations"
  exit 0
fi

# Local socket connections are trusted during init, so each script runs as its owner role.
apply() { # role, database, script
  echo "fiapx: applying $3 as $1"
  psql -v ON_ERROR_STOP=1 --username "$1" --dbname "$2" -f "$scripts/$3"
}
apply identity_svc     identity_db     01-identity_db.sql
apply video_svc        video_db        02-video_db.sql
apply notification_svc notification_db 03-notification_db.sql
