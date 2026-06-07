#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

set -a
# shellcheck disable=SC1091
source .env
set +a

mkdir -p backups
umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

docker compose exec -T mysql \
  mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD}" \
  --single-transaction --routines --events core |
  gzip > "backups/core-${timestamp}.sql.gz"

find backups -type f -name 'core-*.sql.gz' -mtime +7 -delete
echo "Backup local criado em backups/core-${timestamp}.sql.gz"
