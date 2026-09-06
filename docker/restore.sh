#!/usr/bin/env bash
# =============================================================================
# Restore production databases from ./backups.
#   ./docker/restore.sh              # list available backups
#   ./docker/restore.sh backup_file.sql.gz TARGET_DATABASE [postgres|mysql]
#
# Examples:
#   ./docker/restore.sh 20260101-120000-laravel-mysql.sql.gz  laravel mysql
#   ./docker/restore.sh 20260101-120000-vector-postgres.sql.gz vector postgres
# =============================================================================
set -euo pipefail

COMPOSE=(docker compose -f docker-compose.prod.yml --env-file .env.prod)
OUT="backups"

set -a
# shellcheck disable=SC1091
source .env.prod
set +a

backup="$1"; db="${2:-}"
engine="${3:-mysql}"

if [ -z "${backup:-}" ]; then
  echo "Backups in $OUT:"
  ls -lh "$OUT" | cat
  exit 0
fi

FILE="$OUT/$backup"
[ -f "$FILE" ] || { echo "Not found: $FILE"; exit 1; }
[ -n "$db" ] || { echo "Usage: $0 <file.sql.gz> <database> [mysql|postgres]"; exit 1; }

echo "== Restoring '$db' from $backup =="

gunzip -c "$FILE" > "/tmp/restore-$db.sql"

if [ "$engine" = "mysql" ]; then
  "${COMPOSE[@]}" exec -T mysql \
    sh -c "mysql -u'${DB_USERNAME}' -p'${DB_PASSWORD}' '${db}'" \
    < "/tmp/restore-$db.sql"
else
  "${COMPOSE[@]}" exec -T postgres \
    sh -c "psql -U '${VECTOR_DB_USERNAME}' -v ON_ERROR_STOP=1 -d '${db}'" \
    < "/tmp/restore-$db.sql"
fi

rm -f "/tmp/restore-$db.sql"
echo "== Done. =="