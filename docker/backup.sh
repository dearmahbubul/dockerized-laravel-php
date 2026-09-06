#!/usr/bin/env bash
# =============================================================================
# Backup the production databases to ./backups (git-ignored).
# Run from the repo root (script uses docker compose -f docker-compose.prod.yml):
#   ./docker/backup.sh                 # mysql + postgres(laravel+vector)
#   ./docker/backup.sh --all           # + redis rdb + app storage
# Schedule it: 0 2 * * * /path/to/docker/backup.sh >> /var/log/backup.log 2>&1
# =============================================================================
set -euo pipefail

COMPOSE=(docker compose -f docker-compose.prod.yml --env-file .env.prod)
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="backups"
mkdir -p "$OUT"

# Source prod secrets for creds
set -a
# shellcheck disable=SC1091
source .env.prod
set +a

echo "== Backing up to $OUT (stamp $STAMP) =="

# MySQL (primary app DB, or skip if DB_CONNECTION != mysql)
if [ "${DB_CONNECTION:-mysql}" = "mysql" ]; then
  echo "-> mysql: dumping database '${DB_DATABASE}'"
  "${COMPOSE[@]}" exec -T mysql \
    mysqldump -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" \
    | gzip > "$OUT/${DB_DATABASE}-mysql-$STAMP.sql.gz"
fi

# PostgreSQL: always dumps the pgvector 'vector' DB, plus 'laravel' if pgsql primary
for db in "${VECTOR_DB_DATABASE}" \
     $( [ "${DB_CONNECTION:-mysql}" = "pgsql" ] && echo "${DB_DATABASE}" ); do
  echo "-> postgres: dumping database '${db}'"
  "${COMPOSE[@]}" exec -T postgres \
    pg_dump -U "${VECTOR_DB_USERNAME}" -d "${db}" \
    | gzip > "$OUT/${db}-postgres-$STAMP.sql.gz"
done

# Redis AOF/RDB snapshot (optional)
if [ "${1:-}" = "--all" ]; then
  echo "-> redis: copying snapshot"
  "${COMPOSE[@]}" exec -T redis \
    sh -c 'cp /data/dump.rdb /data/redis-dump-$1.rdb' _ || true
  echo "-> app storage: copying volume files"
  "${COMPOSE[@]}" exec -T app sh -c 'cd /var/www && tar czf - storage/app' \
    > "$OUT/app-storage-$STAMP.tgz" || echo "   (storage/app empty; skipped)"
fi

KEEP="${BACKUP_KEEP_DAYS:-7}"
echo "== Pruning backups older than $KEEP days =="
find "$OUT" -name "*$STAMP*" -prune -o -type f -mtime +"$KEEP" -delete
echo "== Done. =="