#!/usr/bin/env bash
# Derruba a stack local.
#
#   ./down.sh        # para os containers (mantem volumes/dados)
#   ./down.sh -v     # para E zera os volumes (apaga MySQL/MinIO/Caddy locais)
set -euo pipefail
cd "$(dirname "$0")"

echo "→ docker compose down $*"
docker compose down "$@"
echo "✓ Pronto."
