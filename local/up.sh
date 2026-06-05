#!/usr/bin/env bash
# Sobe a stack local do ERP Bem Comum.
#
# - No mono_repo: o docker-compose.override.yml (git-ignored) acrescenta a
#   camada de aplicacao (core-api + web + caddy) buildada das pastas-irmas →
#   sobe a STACK COMPLETA (https://app.localhost).
# - Num clone publico do ERP-INFRA: sem override, sobe so a CAMADA DE DADOS
#   (mysql + minio). Os servicos de app ficam como template no compose ate o
#   CI publicar as imagens.
#
#   ./up.sh                # sobe tudo (o que estiver definido)
#   ./up.sh mysql minio    # sobe so os servicos listados (+ deps)
set -euo pipefail
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "✗ docker nao instalado"; exit 1; }
[ -f .env ] || { echo "→ criando .env a partir de .env.example"; cp .env.example .env; }

if [ "$#" -gt 0 ]; then
  echo "→ docker compose up -d --wait $*"
  docker compose up -d --wait "$@"
else
  # Servicos ONE-SHOT (restart: no) saem com 0 de proposito — minio-bootstrap
  # (cria o bucket) e core-api-seed (cria o user dev). Inclui-los no --wait faz
  # o Compose reportar exit 1 ("container parou" = falha). Entao: esperamos os
  # servicos de longa duracao ficarem healthy, depois subimos os one-shots sem
  # --wait (um up -d normal nao falha quando eles saem).
  ONESHOTS='minio-bootstrap|core-api-seed'
  WAIT_SVCS="$(docker compose config --services | grep -vxE "$ONESHOTS" | tr '\n' ' ')"
  echo "→ docker compose up -d --wait $WAIT_SVCS"
  docker compose up -d --wait $WAIT_SVCS
  echo "→ rodando one-shots (bootstrap do bucket + seed do usuario dev)…"
  docker compose up -d
fi

echo
echo "✓ Stack de pe. Servicos disponiveis dependem do que subiu:"
echo "    MinIO console → http://localhost:${MINIO_CONSOLE_PORT:-9001}"
echo "    MySQL         → localhost:${MYSQL_PORT:-3306} (core_app / core_local_dev_only)"
echo "    Stack completa (mono_repo, via override):"
echo "      Front + BFF   → https://app.localhost"
echo "      Swagger back  → https://api.localhost/docs   (DEV-ONLY)"
echo "      Login dev     → ${SEED_EMAIL:-admin@bemcomum.dev} / (SEED_PASSWORD no .env)"
