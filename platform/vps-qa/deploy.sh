#!/usr/bin/env bash
# Deploy idempotente da stack de QA. É o ALVO do forced-command da deploy key
# (GitHub Actions roda `ssh ubuntu@<vm> deploy`). Nunca compila imagem aqui:
# só pull da :qa publicada no ghcr + up. Se um container não ficar healthy,
# `--wait` faz este script sair != 0 e o job de deploy fica vermelho.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Arquivo .env ausente. Copie .env.example para .env e configure." >&2
  exit 1
fi

required_secrets=(
  secrets/mysql-root-password
  secrets/mysql-app-password
  secrets/auth-jwt-private-key.pem
  secrets/auth-jwt-public-key.pem
)
for secret in "${required_secrets[@]}"; do
  if [ ! -s "$secret" ]; then
    echo "Secret ausente ou vazio: $secret (rode ./init-secrets.sh)" >&2
    exit 1
  fi
done

docker compose --env-file .env config --quiet
docker compose --env-file .env pull
docker compose --env-file .env up -d --wait --remove-orphans
docker compose --env-file .env ps
