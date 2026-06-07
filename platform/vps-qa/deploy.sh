#!/usr/bin/env bash
# Deploy de QA disparado pelo GitHub Actions via SSH (forced command no
# authorized_keys). Puxa imagens novas do ghcr e recria só os serviços que
# mudaram. O `up -d --wait` falha (exit != 0) se algum container não ficar
# healthy — assim o run do Actions fica vermelho quando o deploy dá ruim.
set -euo pipefail
cd /opt/erp-qa

echo "[deploy-qa] $(date -u +%FT%TZ) pull..."
docker compose pull

echo "[deploy-qa] up -d --wait..."
docker compose up -d --wait --remove-orphans

echo "[deploy-qa] status:"
docker compose ps --format 'table {{.Service}}\t{{.Status}}'

# prune leve: remove imagens antigas órfãs (libera disco na VPS pequena)
docker image prune -f >/dev/null 2>&1 || true
echo "[deploy-qa] OK"
